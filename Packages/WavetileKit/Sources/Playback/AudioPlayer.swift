import AVFoundation
import JellyfinKit
import MediaPlayer
import Observation
import UIKit

/// The app's audio engine. Owns an `AVQueuePlayer`, a `PlaybackQueue`, Lock Screen /
/// Control Center integration, and Jellyfin session reporting.
///
/// Gapless: the next track is always enqueued behind the current one, so AVFoundation
/// starts it without a gap. Main-actor isolated; AVFoundation does its I/O and decoding on
/// its own threads, so nothing heavy happens here.
@MainActor
@Observable
public final class AudioPlayer {
    public private(set) var queue = PlaybackQueue()
    /// User intent (what the play/pause button shows), independent of buffering.
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var currentTime: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var errorMessage: String?

    public var current: QueuedTrack? { queue.current }

    /// Returns a downloaded file for a track ID; when set, local files play instead of streams.
    @ObservationIgnored public var localFile: ((String) -> URL?)?
    public var hasQueue: Bool { !queue.isEmpty }

    @ObservationIgnored private let library: LibraryClient
    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private var entries: [ObjectIdentifier: Entry] = [:]
    @ObservationIgnored private var statusObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    /// The entry whose play session was reported as started (what "stopped" must refer to).
    @ObservationIgnored private var activeEntry: Entry?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var lastProgressReport = Date.distantPast
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var isSeeking = false

    private struct Entry {
        let track: QueuedTrack
        let playSessionID: String
    }

    public init(library: LibraryClient) {
        self.library = library
        player.automaticallyWaitsToMinimizeStalling = true
        observePlayer()
        observeAudioSession()
        configureRemoteCommands()
    }

    // MARK: - Public controls

    /// Replaces the queue and starts playing at `index`.
    public func play(_ tracks: [QueuedTrack], startAt index: Int = 0, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        queue = PlaybackQueue(tracks: tracks, startAt: index, shuffled: shuffled)
        queue.repeatMode = .off
        isPlaying = true
        loadCurrent()
    }

    public func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    public func resume() {
        guard hasQueue else { return }
        activateSession()
        if player.currentItem == nil { loadCurrent() }
        isPlaying = true
        player.play()
        reportProgress(force: true)
        updateNowPlayingPlayback()
    }

    public func pause() {
        isPlaying = false
        player.pause()
        reportProgress(force: true)
        updateNowPlayingPlayback()
    }

    public func next() {
        guard queue.skipForward() else { return }
        loadCurrent()
    }

    /// Restarts the track if more than 3 s in (standard behavior), otherwise goes back one.
    public func previous() {
        if currentTime > 3 || !queue.skipBackward() {
            seek(to: 0)
        } else {
            loadCurrent()
        }
    }

    public func seek(to seconds: Double) {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        isSeeking = true
        currentTime = seconds
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
                self?.reportProgress(force: true)
                self?.updateNowPlayingPlayback()
            }
        }
    }

    public func jump(to queueID: UUID) {
        queue.jump(to: queueID)
        isPlaying = true
        loadCurrent()
    }

    public func playNext(_ tracks: [QueuedTrack]) {
        if queue.isEmpty { return play(tracks) }
        queue.playNext(tracks)
        enqueueNext()
    }

    public func addToQueue(_ tracks: [QueuedTrack]) {
        if queue.isEmpty { return play(tracks) }
        queue.append(tracks)
        enqueueNext()
    }

    public func remove(_ queueID: UUID) {
        queue.remove(queueID)
        enqueueNext()
    }

    public func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.moveUpNext(fromOffsets: source, toOffset: destination)
        enqueueNext()
    }

    public func toggleShuffle() {
        queue.setShuffle(!queue.isShuffled)
        enqueueNext()
    }

    public func cycleRepeat() {
        queue.cycleRepeat()
        // Repeat-one replays in place; otherwise let the queue player advance by itself.
        player.actionAtItemEnd = queue.repeatMode == .one ? .pause : .advance
        enqueueNext()
    }

    /// Stops playback and clears the queue (sign out).
    public func stop() {
        reportStopped()
        player.pause()
        forgetAllItems()
        queue = PlaybackQueue()
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Queue → AVQueuePlayer

    /// Rebuilds the player around the queue's current track and starts it if playing.
    private func loadCurrent() {
        reportStopped()
        forgetAllItems()
        errorMessage = nil
        currentTime = 0
        guard let track = queue.current, let item = makeItem(for: track) else { return }
        player.insert(item, after: nil)
        duration = track.duration.map { Double($0.components.seconds) } ?? 0
        enqueueNext()
        if isPlaying {
            activateSession()
            player.play()
        }
        didStart(track)
    }

    /// Ensures exactly one preloaded item (the automatic next track) follows the current item.
    private func enqueueNext() {
        for item in player.items().dropFirst() {
            player.remove(item)
            entries.removeValue(forKey: ObjectIdentifier(item))
            statusObservations.removeValue(forKey: ObjectIdentifier(item))
        }
        guard queue.repeatMode != .one, let next = queue.automaticNext, next.queueID != queue.current?.queueID,
              let currentItem = player.currentItem, let item = makeItem(for: next)
        else { return }
        player.insert(item, after: currentItem)
    }

    private func forgetAllItems() {
        player.removeAllItems()
        entries.removeAll()
        statusObservations.removeAll()
    }

    private func makeItem(for track: QueuedTrack) -> AVPlayerItem? {
        if let file = localFile?(track.trackID) {
            let item = AVPlayerItem(url: file)
            entries[ObjectIdentifier(item)] = Entry(track: track, playSessionID: UUID().uuidString)
            observeStatus(of: item)
            return item
        }
        guard let request = library.streamRequest(trackID: track.trackID) else { return nil }
        // Header-based auth keeps the token out of the URL.
        let asset = AVURLAsset(url: request.url, options: ["AVURLAssetHTTPHeaderFieldsKey": request.headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        entries[ObjectIdentifier(item)] = Entry(track: track, playSessionID: request.playSessionID)
        observeStatus(of: item)
        return item
    }

    /// AVQueuePlayer moved to a new item on its own (gapless advance) or ran out of items.
    private func currentItemChanged(to item: AVPlayerItem?) {
        guard let item else {
            // End of queue without repeat: rewind to the last track, paused.
            guard hasQueue, player.items().isEmpty, !isSeeking else { return }
            reportStopped()
            isPlaying = false
            loadCurrent()
            return
        }
        guard let entry = entries[ObjectIdentifier(item)], entry.track.queueID != queue.current?.queueID else { return }
        reportStopped()
        if entry.track.queueID == queue.automaticNext?.queueID {
            _ = queue.advanceAutomatically()
        } else {
            queue.jump(to: entry.track.queueID)
        }
        duration = entry.track.duration.map { Double($0.components.seconds) } ?? 0
        currentTime = 0
        enqueueNext()
        didStart(entry.track)
    }

    private func didStart(_ track: QueuedTrack) {
        lastProgressReport = Date()
        activeEntry = currentEntry
        if let entry = activeEntry {
            Task { await library.reportStart(trackID: track.trackID, playSessionID: entry.playSessionID, positionSeconds: 0, isPaused: !isPlaying) }
        }
        updateNowPlayingMetadata(track)
    }

    private var currentEntry: Entry? {
        player.currentItem.flatMap { entries[ObjectIdentifier($0)] }
    }

    // MARK: - Observation

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.reportProgress(force: false)
            }
        }

        observations.append(player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            let item = player.currentItem
            Task { @MainActor in self?.currentItemChanged(to: item) }
        })

        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor in self?.isBuffering = waiting }
        })

        // Repeat-one: the item pauses at its end (actionAtItemEnd = .pause); restart it as a new play.
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let item = note.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, self.queue.repeatMode == .one, item === self.player.currentItem, let track = self.queue.current else { return }
                self.reportStopped()
                self.player.seek(to: .zero)
                self.player.play()
                self.didStart(track)
            }
        })
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservations[ObjectIdentifier(item)] = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                self.errorMessage = message ?? "This track couldn't be played."
                // Skip unplayable tracks rather than stalling the queue.
                if self.queue.skipForward() { self.loadCurrent() } else { self.pause() }
            }
        }
    }

    // MARK: - Audio session

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        // Long-form audio routes AirPlay 2 like Music/Podcasts.
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? session.setActive(true)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init) ?? []
            MainActor.assumeIsolated {
                guard let self else { return }
                switch type {
                case .began:
                    // Keep intent so we can resume; just stop the clock.
                    self.player.pause()
                    self.updateNowPlayingPlayback()
                case .ended where options.contains(.shouldResume) && self.isPlaying:
                    self.resume()
                case .ended:
                    self.isPlaying = false
                    self.updateNowPlayingPlayback()
                default:
                    break
                }
            }
        })

        // Headphones unplugged / Bluetooth disconnected: pause instead of blasting the speaker.
        notificationTokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
        })
    }

    // MARK: - Lock Screen / Control Center

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated { self?.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlayingMetadata(_ track: QueuedTrack) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo,
           existing[MPMediaItemPropertyAlbumTitle] as? String == track.albumTitle {
            info[MPMediaItemPropertyArtwork] = existing[MPMediaItemPropertyArtwork]
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtwork(for: track)
    }

    private func updateNowPlayingPlayback() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for track: QueuedTrack) {
        artworkTask?.cancel()
        guard let albumID = track.albumID,
              let url = library.imageURL(itemID: albumID, tag: track.albumImageTag, maxPixelWidth: 600)
        else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data), !Task.isCancelled,
                  self?.queue.current?.queueID == track.queueID
            else { return }
            let artwork = Self.makeArtwork(image)
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    /// MediaPlayer invokes the image handler on its own queue. Built in a nonisolated context so
    /// the closure doesn't inherit main-actor isolation (which traps when called off-main).
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    // MARK: - Jellyfin reporting

    private func reportProgress(force: Bool) {
        guard let entry = activeEntry else { return }
        let track = entry.track
        guard force || Date().timeIntervalSince(lastProgressReport) >= 10 else { return }
        lastProgressReport = Date()
        let position = currentTime, paused = !isPlaying
        Task { await library.reportProgress(trackID: track.trackID, playSessionID: entry.playSessionID, positionSeconds: position, isPaused: paused) }
    }

    private func reportStopped() {
        guard let entry = activeEntry else { return }
        activeEntry = nil
        let track = entry.track
        let position = currentTime
        Task { await library.reportStopped(trackID: track.trackID, playSessionID: entry.playSessionID, positionSeconds: position) }
    }
}
