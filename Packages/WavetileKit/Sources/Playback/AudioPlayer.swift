import AVFoundation
import JellyfinKit
import MediaPlayer
import Observation
import UIKit

/// The app's audio engine. Owns an `AVQueuePlayer`, a `PlaybackQueue`, Lock Screen /
/// Control Center integration, and Jellyfin session reporting.
///
/// Podcast episodes play through the same engine: they stream from the publisher without the
/// Jellyfin token, resume where they left off, honor `podcastRate`, and report progress through
/// `onEpisodeProgress` instead of to Jellyfin.
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

    /// Speed for podcast episodes. Music always plays at 1×.
    public var podcastRate: Float = 1 {
        didSet { applyRate() }
    }
    /// Seconds jumped by the skip buttons (episodes) and the Lock Screen skip commands.
    public var skipBackInterval: Double = 15 {
        didSet { configureSkipIntervals() }
    }
    public var skipForwardInterval: Double = 30 {
        didSet { configureSkipIntervals() }
    }

    public enum SleepTimer: Equatable, Sendable {
        case at(Date)
        case endOfItem
    }

    /// Pauses playback at a time, or when the current item finishes.
    public private(set) var sleepTimer: SleepTimer?

    /// Turns loud songs down to Jellyfin's loudness target (like Sound Check), so tracks from
    /// different albums play at a similar volume. Applies from the next song that loads.
    public var levelsVolume = UserDefaults.standard.object(forKey: "levelsVolume") as? Bool ?? true {
        didSet { UserDefaults.standard.set(levelsVolume, forKey: "levelsVolume") }
    }

    /// The rate the current item plays at when playing.
    public var effectiveRate: Float { current?.isEpisode == true ? podcastRate : 1 }

    /// Saved position for an episode (seconds); playback starts there.
    @ObservationIgnored public var resumePosition: ((QueuedTrack) -> Double?)?
    /// Episode progress, every few seconds while playing and whenever it stops (position, duration).
    @ObservationIgnored public var onEpisodeProgress: ((QueuedTrack, Double, Double) -> Void)?
    /// A song was listened to but its stop report didn't reach Jellyfin (offline): track ID and
    /// when it was played, to be sent later.
    @ObservationIgnored public var onUnreportedPlay: ((String, Date) -> Void)?

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
    @ObservationIgnored private var sleepTask: Task<Void, Never>?

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

    /// Jumps forward (positive) or back (negative) within the current item.
    public func skip(by seconds: Double) {
        let end = duration > 0 ? duration - 1 : .greatestFiniteMagnitude
        seek(to: min(max(0, currentTime + seconds), end))
    }

    public func setSleepTimer(_ timer: SleepTimer?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimer = timer
        updateActionAtItemEnd()
        guard case let .at(date) = timer else { return }
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            self.sleepTimer = nil
            self.pause()
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
        updateActionAtItemEnd()
        enqueueNext()
    }

    /// Repeat-one replays in place and the end-of-episode sleep timer stops there; otherwise the
    /// queue player advances by itself.
    private func updateActionAtItemEnd() {
        player.actionAtItemEnd = loopsCurrent || sleepTimer == .endOfItem ? .pause : .advance
    }

    /// The current item plays again at its end: repeat-one, or repeat-all with a one-track
    /// queue (whose next track is itself, which AVQueuePlayer can't preload behind it).
    private var loopsCurrent: Bool {
        queue.repeatMode == .one
            || (queue.repeatMode == .all && queue.current != nil && queue.automaticNext?.queueID == queue.current?.queueID)
    }

    /// Stops playback and clears the queue (sign out).
    public func stop() {
        reportStopped()
        setSleepTimer(nil)
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
        applyRate()
        seekToResumePosition(track)
        if isPlaying {
            activateSession()
            player.play()
        }
        didStart(track)
    }

    /// Episodes pick up where the listener left off (positions under 5 s start from the top).
    private func seekToResumePosition(_ track: QueuedTrack) {
        guard track.isEpisode, let position = resumePosition?(track), position > 5 else { return }
        isSeeking = true
        currentTime = position
        // A second of tolerance: exact seeks in long MP3s can scan the whole file.
        let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in self?.isSeeking = false }
        }
    }

    /// Ensures exactly one preloaded item (the automatic next track) follows the current item.
    private func enqueueNext() {
        // Queue edits can start or stop a one-track loop.
        updateActionAtItemEnd()
        // Keep a preloaded item that's still the right one: rebuilding it on every queue edit
        // throws away what it has buffered and risks a gap near the end of the current track.
        let preloaded = player.items().dropFirst()
        if !loopsCurrent, let next = queue.automaticNext, next.queueID != queue.current?.queueID,
           preloaded.count == 1, let item = preloaded.first, item.status != .failed,
           entries[ObjectIdentifier(item)]?.track.queueID == next.queueID {
            return
        }
        for item in preloaded {
            player.remove(item)
            entries.removeValue(forKey: ObjectIdentifier(item))
            statusObservations.removeValue(forKey: ObjectIdentifier(item))
        }
        guard !loopsCurrent, let next = queue.automaticNext, next.queueID != queue.current?.queueID,
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
            if track.isEpisode { item.audioTimePitchAlgorithm = .timeDomain } else { level(item, gain: track.normalizationGain) }
            entries[ObjectIdentifier(item)] = Entry(track: track, playSessionID: UUID().uuidString)
            observeStatus(of: item)
            return item
        }
        if let podcast = track.podcast {
            // Security: a plain asset with no headers. The Jellyfin token must never reach a podcast host.
            let item = AVPlayerItem(asset: AVURLAsset(url: podcast.audioURL))
            // Speech-friendly time stretching for 1.5×, 2× and so on.
            item.audioTimePitchAlgorithm = .timeDomain
            item.preferredForwardBufferDuration = 60
            entries[ObjectIdentifier(item)] = Entry(track: track, playSessionID: "")
            observeStatus(of: item)
            return item
        }
        guard let request = library.streamRequest(trackID: track.trackID) else { return nil }
        // Header-based auth keeps the token out of the URL.
        let asset = AVURLAsset(url: request.url, options: ["AVURLAssetHTTPHeaderFieldsKey": request.headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        level(item, gain: track.normalizationGain)
        entries[ObjectIdentifier(item)] = Entry(track: track, playSessionID: request.playSessionID)
        observeStatus(of: item)
        return item
    }

    /// Volume levelling through the item's audio mix, so each song in a gapless run carries its
    /// own level. Only turns down: boosting a quiet song past full scale would clip.
    private func level(_ item: AVPlayerItem, gain: Double?) {
        guard levelsVolume, let gain, gain < 0 else { return }
        let volume = Float(pow(10, gain / 20))
        Task {
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(volume, at: .zero)
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            item.audioMix = mix
        }
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
        // Forget items AVQueuePlayer has moved past, so a long gapless run doesn't pile them up.
        let live = Set(player.items().map(ObjectIdentifier.init))
        for key in entries.keys where !live.contains(key) {
            entries.removeValue(forKey: key)
            statusObservations.removeValue(forKey: key)
        }
        reportStopped()
        if entry.track.queueID == queue.automaticNext?.queueID {
            _ = queue.advanceAutomatically()
        } else {
            queue.jump(to: entry.track.queueID)
        }
        duration = entry.track.duration.map { Double($0.components.seconds) } ?? 0
        currentTime = 0
        enqueueNext()
        applyRate()
        seekToResumePosition(entry.track)
        didStart(entry.track)
        // A preloaded item can fail before it's current; its status observer ignores it then.
        if item.status == .failed { itemFailed(item) }
    }

    private func didStart(_ track: QueuedTrack) {
        lastProgressReport = Date()
        activeEntry = currentEntry
        if let entry = activeEntry, !track.isEpisode {
            Task { await library.reportStart(trackID: track.trackID, playSessionID: entry.playSessionID, positionSeconds: 0, isPaused: !isPlaying) }
        }
        enableCommands(forEpisode: track.isEpisode)
        updateNowPlayingMetadata(track)
    }

    /// Applies the current item's rate. `defaultRate` makes `play()` (and AirPods/Lock Screen
    /// play) resume at that speed.
    private func applyRate() {
        let rate = effectiveRate
        player.defaultRate = rate
        if isPlaying, player.rate != 0, player.rate != rate { player.rate = rate }
        updateNowPlayingPlayback()
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

        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let item = note.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, let item else { return }
                self.itemDidPlayToEnd(item)
            }
        })
    }

    private func itemDidPlayToEnd(_ item: AVPlayerItem) {
        // A finished episode is played all the way through, whatever the last clock tick said.
        if let entry = entries[ObjectIdentifier(item)], entry.track.isEpisode {
            let length = item.duration.seconds.isFinite ? item.duration.seconds : duration
            onEpisodeProgress?(entry.track, length, length)
        }
        guard item === player.currentItem else { return }
        // End-of-episode sleep timer: the item paused at its end (actionAtItemEnd = .pause).
        // Stop, and cue up the next item without playing it.
        if sleepTimer == .endOfItem {
            reportStopped()
            sleepTimer = nil
            isPlaying = false
            updateActionAtItemEnd()
            _ = queue.skipForward()
            loadCurrent()
            updateNowPlayingPlayback()
            return
        }
        // Looping one item: it pauses at its end (actionAtItemEnd = .pause); restart it as a new play.
        guard loopsCurrent, let track = queue.current else { return }
        reportStopped()
        player.seek(to: .zero)
        player.play()
        didStart(track)
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservations[ObjectIdentifier(item)] = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                self.itemFailed(item)
            }
        }
    }

    private func itemFailed(_ item: AVPlayerItem) {
        let fallback = queue.current?.isEpisode == true ? "This episode couldn't be played." : "This track couldn't be played."
        errorMessage = item.error?.localizedDescription ?? fallback
        // Skip unplayable tracks rather than stalling the queue.
        if queue.skipForward() { loadCurrent() } else { pause() }
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
        commands.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval
            MainActor.assumeIsolated {
                guard let self else { return }
                self.skip(by: -(interval ?? self.skipBackInterval))
            }
            return .success
        }
        commands.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval
            MainActor.assumeIsolated {
                guard let self else { return }
                self.skip(by: interval ?? self.skipForwardInterval)
            }
            return .success
        }
        commands.changePlaybackRateCommand.supportedPlaybackRates = Self.podcastRates.map { NSNumber(value: $0) }
        commands.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let rate = (event as? MPChangePlaybackRateCommandEvent)?.playbackRate else { return .commandFailed }
            MainActor.assumeIsolated { self?.podcastRate = rate }
            return .success
        }
        configureSkipIntervals()
        enableCommands(forEpisode: false)
    }

    /// Speeds offered for podcasts (the player's speed menu and the Lock Screen).
    public static let podcastRates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    private func configureSkipIntervals() {
        let commands = MPRemoteCommandCenter.shared()
        commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackInterval)]
        commands.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardInterval)]
    }

    /// Lock Screen shows skip-back/skip-forward for episodes (like Podcasts) and previous/next for music.
    private func enableCommands(forEpisode isEpisode: Bool) {
        let commands = MPRemoteCommandCenter.shared()
        commands.skipBackwardCommand.isEnabled = isEpisode
        commands.skipForwardCommand.isEnabled = isEpisode
        commands.changePlaybackRateCommand.isEnabled = isEpisode
        commands.nextTrackCommand.isEnabled = !isEpisode
        commands.previousTrackCommand.isEnabled = !isEpisode
    }

    private func updateNowPlayingMetadata(_ track: QueuedTrack) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(effectiveRate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(effectiveRate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo,
           existing[MPMediaItemPropertyAlbumTitle] as? String == track.albumTitle {
            info[MPMediaItemPropertyArtwork] = existing[MPMediaItemPropertyArtwork]
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        // Same album, same art: keep it rather than downloading it again for every track.
        if info[MPMediaItemPropertyArtwork] == nil || track.isEpisode { loadArtwork(for: track) }
    }

    private func updateNowPlayingPlayback() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(effectiveRate) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(effectiveRate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for track: QueuedTrack) {
        artworkTask?.cancel()
        guard let url = track.podcast?.artworkURL
            ?? track.albumID.flatMap({ library.imageURL(itemID: $0, tag: track.albumImageTag, maxPixelWidth: 600) })
        else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = await Self.decodeArtwork(data), !Task.isCancelled,
                  self?.queue.current?.queueID == track.queueID
            else { return }
            let artwork = Self.makeArtwork(image)
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    /// Decoded off the main actor and scaled down: third-party podcast art can be 3000 px.
    @concurrent private nonisolated static func decodeArtwork(_ data: Data) async -> UIImage? {
        UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 600, height: 600))
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
        // Episodes save locally, so they can afford finer-grained resume points.
        guard force || Date().timeIntervalSince(lastProgressReport) >= (track.isEpisode ? 5 : 10) else { return }
        lastProgressReport = Date()
        if track.isEpisode {
            guard !isSeeking else { return }
            onEpisodeProgress?(track, currentTime, duration)
            return
        }
        let position = currentTime, paused = !isPlaying
        Task { await library.reportProgress(trackID: track.trackID, playSessionID: entry.playSessionID, positionSeconds: position, isPaused: paused) }
    }

    private func reportStopped() {
        guard let entry = activeEntry else { return }
        activeEntry = nil
        let track = entry.track
        let position = currentTime
        if track.isEpisode {
            onEpisodeProgress?(track, position, duration)
            return
        }
        let length = duration, playedAt = Date()
        Task {
            let reported = await library.reportStopped(trackID: track.trackID, playSessionID: entry.playSessionID, positionSeconds: position)
            if !reported, Self.countsAsPlay(position: position, duration: length) { onUnreportedPlay?(track.trackID, playedAt) }
        }
    }

    /// The usual scrobbling rule: half the song, or four minutes of a long one.
    nonisolated static func countsAsPlay(position: Double, duration: Double) -> Bool {
        guard position.isFinite, position > 0 else { return false }
        return position >= 240 || (duration > 0 && position >= duration / 2)
    }
}
