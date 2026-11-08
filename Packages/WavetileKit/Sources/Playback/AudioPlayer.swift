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
    /// Set when something couldn't play because it can't stream right now (offline, or the
    /// server is out of reach) and it isn't downloaded.
    /// A new value each time, so the app shows its toast again on every attempt.
    public private(set) var offlineNotice: OfflineNotice?

    public struct OfflineNotice: Equatable, Sendable {
        public let id = UUID()
    }

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
    /// Whether a track can stream right now (the network is up and, for music, the server
    /// answers). When it can't, only what's on the device is queued.
    @ObservationIgnored public var canStream: ((QueuedTrack) -> Bool)?
    /// Whether a track is downloaded, answered from memory: `play()` asks it of every track in
    /// the list, which can be the whole library.
    @ObservationIgnored public var isOnDevice: ((QueuedTrack) -> Bool)?
    /// A stream failed to connect: rechecks whether its source is reachable, returning once
    /// `canStream` has the answer.
    @ObservationIgnored public var onConnectionError: ((QueuedTrack) async -> Void)?
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
    /// Tracks in a row that failed to play; reset once something plays for a moment.
    @ObservationIgnored private var consecutiveFailures = 0
    /// After this many failures in a row (an expired sign-in, a server error) playback stops
    /// instead of skipping on, which under repeat-all would wrap around the queue forever.
    private static let maxConsecutiveFailures = 10

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
    /// When some tracks can't stream, queues only the playable ones, starting at the first from
    /// `index`; with none playable it plays nothing, posts `offlineNotice` and returns false.
    @discardableResult
    public func play(_ tracks: [QueuedTrack], startAt index: Int = 0, shuffled: Bool = false) -> Bool {
        guard !tracks.isEmpty else { return false }
        var tracks = tracks, index = index
        let playable = tracks.indices.filter { canPlay(tracks[$0]) }
        guard !playable.isEmpty else {
            notifyOffline()
            return false
        }
        if playable.count < tracks.count {
            index = playable.firstIndex { $0 >= index } ?? 0
            tracks = playable.map { tracks[$0] }
        }
        queue = PlaybackQueue(tracks: tracks, startAt: index, shuffled: shuffled)
        queue.repeatMode = .off
        consecutiveFailures = 0
        isPlaying = true
        loadCurrent()
        return true
    }

    public func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    public func resume() {
        guard hasQueue else { return }
        if player.currentItem == nil || player.currentItem?.status == .failed { loadCurrent() }
        isPlaying = true
        playOnceSessionIsActive()
        reportProgress(force: true)
        updateNowPlayingPlayback()
    }

    public func pause() {
        isPlaying = false
        player.pause()
        reportProgress(force: true)
        updateNowPlayingPlayback()
    }

    /// Skips past tracks that can't play now; with none ahead, stays put and says why.
    public func next() {
        guard move(by: { $0.skipForward() }) else { return }
        loadCurrent()
    }

    /// Restarts the track if more than 3 s in (standard behavior), otherwise goes back to the
    /// previous playable track.
    public func previous() {
        if currentTime > 3 || !move(by: { $0.skipBackward() }) {
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
        if let track = queue.items.first(where: { $0.queueID == queueID }), !canPlay(track) {
            return notifyOffline()
        }
        queue.jump(to: queueID)
        consecutiveFailures = 0
        isPlaying = true
        loadCurrent()
    }

    public func playNext(_ tracks: [QueuedTrack]) {
        if queue.isEmpty { return _ = play(tracks) }
        guard let tracks = playableNow(tracks) else { return }
        queue.playNext(tracks)
        enqueueNext()
    }

    public func addToQueue(_ tracks: [QueuedTrack]) {
        if queue.isEmpty { return _ = play(tracks) }
        guard let tracks = playableNow(tracks) else { return }
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
        deactivateSession()
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
        if isPlaying { playOnceSessionIsActive() }
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
        let target = preloadTarget
        if !loopsCurrent, let next = target, next.queueID != queue.current?.queueID,
           preloaded.count == 1, let item = preloaded.first, item.status != .failed,
           entries[ObjectIdentifier(item)]?.track.queueID == next.queueID {
            return
        }
        for item in preloaded {
            player.remove(item)
            entries.removeValue(forKey: ObjectIdentifier(item))
            statusObservations.removeValue(forKey: ObjectIdentifier(item))
        }
        guard !loopsCurrent, let next = target, next.queueID != queue.current?.queueID,
              let currentItem = player.currentItem, let item = makeItem(for: next)
        else { return }
        player.insert(item, after: currentItem)
    }

    /// The automatic next track, or the first playable one after it, so the gapless item isn't a
    /// stream that's sure to fail. AVQueuePlayer moving to it jumps the queue past the rest.
    private var preloadTarget: QueuedTrack? {
        guard let next = queue.automaticNext else { return nil }
        if canPlay(next) { return next }
        var probe = queue
        for _ in queue.items.indices {
            guard probe.skipForward(), let track = probe.current else { return nil }
            if canPlay(track) { return track }
        }
        return nil
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
                if self.currentTime >= 1 { self.consecutiveFailures = 0 }
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
        guard let track = queue.current else { return }
        // Confirm before treating the source as down: one slow or dropped stream isn't an outage.
        if Self.isConnectionError(item.error), let recheck = onConnectionError {
            Task {
                await recheck(track)
                // Unless the listener has moved on in the meantime.
                guard queue.current?.queueID == track.queueID else { return }
                skipFailed(item, track)
            }
            return
        }
        skipFailed(item, track)
    }

    private func skipFailed(_ item: AVPlayerItem, _ track: QueuedTrack) {
        // The connection or server is gone: skip to what's playable (saying so once), rather
        // than failing through the rest of the queue one track at a time.
        if !canPlay(track) {
            // Paused (the rewind at the end of a queue): nothing to skip or say until play is pressed.
            guard isPlaying else { return }
            notifyOffline()
            if move(by: { $0.skipForward() }) { loadCurrent() } else { pause() }
            return
        }
        let fallback = queue.current?.isEpisode == true ? "This episode couldn't be played." : "This track couldn't be played."
        errorMessage = item.error?.localizedDescription ?? fallback
        consecutiveFailures += 1
        if consecutiveFailures >= min(queue.items.count, Self.maxConsecutiveFailures) {
            consecutiveFailures = 0
            pause()
            return
        }
        // Skip unplayable tracks rather than stalling the queue.
        if queue.skipForward() { loadCurrent() } else { pause() }
    }

    // MARK: - Offline

    /// Streaming is checked first: it's free, and the common case.
    private func canPlay(_ track: QueuedTrack) -> Bool {
        canStream?(track) != false || isOnDevice?(track) ?? (localFile?(track.trackID) != nil)
    }

    private func notifyOffline() {
        offlineNotice = OfflineNotice()
    }

    /// The tracks that can play now; nil (after posting the notice) if none can.
    private func playableNow(_ tracks: [QueuedTrack]) -> [QueuedTrack]? {
        let playable = tracks.filter(canPlay)
        if playable.isEmpty { notifyOffline() }
        return playable.isEmpty ? nil : playable
    }

    /// Steps the queue until it lands on a playable track (at most once around a repeating
    /// queue). Passing over tracks that can't play posts the notice; with none playable the
    /// queue stays where it was.
    private func move(by step: (inout PlaybackQueue) -> Bool) -> Bool {
        var probe = queue
        for passed in queue.items.indices {
            guard step(&probe), let track = probe.current else { break }
            if canPlay(track) {
                if passed > 0 { notifyOffline() }
                queue = probe
                return true
            }
        }
        if probe.current?.queueID != queue.current?.queueID { notifyOffline() }
        return false
    }

    /// No network, or the host didn't answer. AVFoundation wraps the URL error, so look one
    /// level down too.
    private nonisolated static func isConnectionError(_ error: (any Error)?) -> Bool {
        guard let error = error as NSError? else { return false }
        let codes = [
            NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed,
            NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorTimedOut,
        ]
        return ([error] + error.underlyingErrors.map { $0 as NSError }).contains {
            $0.domain == NSURLErrorDomain && codes.contains($0.code)
        }
    }

    // MARK: - Audio session

    /// Session changes run in call order on one background queue: `setActive` can block for a
    /// good while (a route change, another app's audio), and on the main thread that freezes the UI.
    private static let sessionQueue = DispatchQueue(label: "com.derrellwilliams.wavetile.audio-session", qos: .userInitiated)

    /// Bumped by every session request; a pending start that was overtaken (a newer play, a pause,
    /// a stop) sees a different value and does nothing.
    @ObservationIgnored private var sessionRequest = 0

    /// Sets the category and activates the session off the main thread, then plays, so playback
    /// still starts only after the category is set and the session is active, as before. Does
    /// nothing if the listener paused or stopped in the meantime.
    private func playOnceSessionIsActive() {
        sessionRequest += 1
        let request = sessionRequest
        Self.sessionQueue.async { [weak self] in
            Self.activate()
            Task { @MainActor in
                guard let self, request == self.sessionRequest, self.isPlaying else { return }
                self.player.play()
            }
        }
    }

    private func deactivateSession() {
        sessionRequest += 1
        Self.sessionQueue.async { Self.deactivate() }
    }

    private nonisolated static func activate() {
        let session = AVAudioSession.sharedInstance()
        // Long-form audio routes AirPlay 2 like Music/Podcasts.
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? session.setActive(true)
    }

    private nonisolated static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
            guard let data = await Self.fetchArtwork(url),
                  let image = await Self.decodeArtwork(data), !Task.isCancelled,
                  self?.queue.current?.queueID == track.queueID
            else { return }
            let artwork = Self.makeArtwork(image)
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    /// Security: podcast art comes from any host a feed names, so it's fetched with no cookies or
    /// credentials, and capped in size so a hostile host can't fill memory.
    private nonisolated static let artworkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private nonisolated static let maxArtworkBytes = 10 * 1024 * 1024

    @concurrent private nonisolated static func fetchArtwork(_ url: URL) async -> Data? {
        guard let (bytes, response) = try? await artworkSession.bytes(from: url),
              (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) ?? true,
              response.expectedContentLength <= maxArtworkBytes
        else { return nil }
        // Appends in 64 KB chunks: per-byte `Data.append` is slow on a big image.
        var data = Data()
        var chunk: [UInt8] = []
        chunk.reserveCapacity(65_536)
        do {
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count == 65_536 {
                    data.append(contentsOf: chunk)
                    chunk.removeAll(keepingCapacity: true)
                    if data.count > maxArtworkBytes { return nil }
                }
            }
        } catch {
            return nil
        }
        data.append(contentsOf: chunk)
        return data.count <= maxArtworkBytes ? data : nil
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
