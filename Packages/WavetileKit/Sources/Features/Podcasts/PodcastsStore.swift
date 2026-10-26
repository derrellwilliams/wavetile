import DesignSystem
import Foundation
import GRDB
import JellyfinKit
import Observation
import os
import Playback
import Podcasts

/// The signed-in user's podcasts: settings, subscriptions, listening progress, Up Next,
/// downloads and sync. Present for every user; the Podcasts tab, search scope and downloads
/// filter only appear when `isEnabled` (off by default; turned on from the profile drawer).
@Observable
final class PodcastsStore {
    let database: PodcastDatabase
    let fetcher: FeedFetcher
    let directory = DirectoryClient()
    let downloads: EpisodeDownloadManager?
    @ObservationIgnored private let library: LibraryClient
    @ObservationIgnored private let player: AudioPlayer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keyPrefix: String
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.derrellwilliams.wavetile", category: "podcasts")

    // MARK: Settings (per user)

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: key("enabled"))
            defaults.set(Date().timeIntervalSince1970, forKey: key("enabledUpdated"))
            schedulePush()
        }
    }

    var hasSeenIntro: Bool {
        didSet { defaults.set(hasSeenIntro, forKey: key("introSeen")) }
    }

    var skipBack: Double {
        didSet {
            defaults.set(skipBack, forKey: key("skipBack"))
            player.skipBackInterval = skipBack
        }
    }

    var skipForward: Double {
        didSet {
            defaults.set(skipForward, forKey: key("skipForward"))
            player.skipForwardInterval = skipForward
        }
    }

    /// Default speed for shows without their own.
    var defaultRate: Double {
        didSet { defaults.set(defaultRate, forKey: key("rate")) }
    }

    /// Newest episodes kept downloaded for each auto-download show (0 = off).
    var autoDownloadCount: Int {
        didSet {
            defaults.set(autoDownloadCount, forKey: key("autoDownload"))
            Task { await autoDownload() }
        }
    }

    var deletePlayedDownloads: Bool {
        didSet { defaults.set(deletePlayedDownloads, forKey: key("deletePlayed")) }
    }

    /// Mirror subscriptions and progress to the user's Jellyfin account.
    var syncWithJellyfin: Bool {
        didSet {
            defaults.set(syncWithJellyfin, forKey: key("sync"))
            if syncWithJellyfin { Task { await sync() } }
        }
    }

    // MARK: Live state

    private(set) var downloadStates: [String: EpisodeDownloadRecord] = [:]
    private(set) var totalBytes: Int64 = 0
    private(set) var isRefreshing = false

    init(session: ServerSession, library: LibraryClient, player: AudioPlayer, database: PodcastDatabase, defaults: UserDefaults = .standard) {
        self.database = database
        self.library = library
        self.player = player
        self.defaults = defaults
        self.fetcher = FeedFetcher(database: database)
        self.downloads = try? EpisodeDownloadManager(serverID: session.serverID, userID: session.userID, database: database)
        self.keyPrefix = "podcasts.\(session.userID)."
        let prefix = keyPrefix
        func value<T>(_ name: String, _ fallback: T) -> T { defaults.object(forKey: prefix + name) as? T ?? fallback }
        isEnabled = value("enabled", false)
        hasSeenIntro = value("introSeen", false)
        skipBack = value("skipBack", 15)
        skipForward = value("skipForward", 30)
        defaultRate = value("rate", 1)
        autoDownloadCount = value("autoDownload", 0)
        deletePlayedDownloads = value("deletePlayed", true)
        syncWithJellyfin = value("sync", true)
        player.skipBackInterval = skipBack
        player.skipForwardInterval = skipForward
    }

    private func key(_ name: String) -> String { keyPrefix + name }

    /// Live stream of a query's results; ends when the observing task is cancelled.
    func observe<T: Sendable>(_ observation: ValueObservation<ValueReducers.Fetch<T>>) -> AsyncValueObservation<T> {
        observation.values(in: database.pool)
    }

    /// Long-running: download badges, storage, resumed downloads, sync and a refresh when stale.
    /// Run from a view `.task`.
    func run() async {
        async let states: Void = observeDownloads()
        async let bytes: Void = observeBytes()
        async let startup: Void = startup()
        _ = await (states, bytes, startup)
    }

    private func observeDownloads() async {
        do {
            for try await states in observe(database.downloadStates()) { downloadStates = states }
        } catch { Log.observationFailed(error) }
    }

    private func observeBytes() async {
        do {
            for try await bytes in observe(database.totalDownloadedBytes()) { totalBytes = bytes }
        } catch { Log.observationFailed(error) }
    }

    private func startup() async {
        await downloads?.resumePending(allowCellular: allowCellular)
        if let names = try? await database.removeUnfollowedShows() { downloads?.deleteFiles(names) }
        await sync()
        guard isEnabled else { return }
        let stale = ((try? database.followedShowsNow()) ?? []).contains { ($0.lastRefreshed ?? .distantPast) < Date().addingTimeInterval(-3600) }
        if stale { await refreshAll() }
    }

    private var allowCellular: Bool {
        // Shares the "Use Cellular Data" download setting with music.
        defaults.object(forKey: "downloadOverCellular") as? Bool ?? false
    }

    // MARK: - Shows

    /// Refreshes every followed show, then applies auto-download.
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        _ = await fetcher.refreshAll()
        await autoDownload()
    }

    /// Loads a show for its page: cached when fresh, otherwise fetched (followed or as a preview).
    func loadShow(feedURL: URL) async throws -> ShowRecord {
        let id = PodcastID.show(feedURL: feedURL)
        if let show = try database.showNow(id: id), (show.lastRefreshed ?? .distantPast) > Date().addingTimeInterval(-900) {
            return show
        }
        return try await fetcher.load(feedURL: feedURL, follow: false).show
    }

    func refresh(_ show: ShowRecord) async {
        _ = try? await fetcher.refresh(show)
    }

    func follow(feedURL: URL) async throws -> ShowRecord {
        let show = try await fetcher.load(feedURL: feedURL, follow: true).show
        try await database.updateShow(id: show.id) { $0.autoDownload = true }
        subscriptionsChanged()
        await autoDownload()
        return show
    }

    func setFollowed(_ show: ShowRecord, _ followed: Bool) async {
        if followed {
            _ = try? await follow(feedURL: show.feedURL)
            return
        }
        try? await database.setFollowed(showID: show.id, false)
        subscriptionsChanged()
    }

    func updateShow(_ show: ShowRecord, _ change: @escaping @Sendable (inout ShowRecord) -> Void) {
        Task { try? await database.updateShow(id: show.id, change) }
    }

    func markOpened(_ show: ShowRecord) {
        guard show.isFollowed else { return }
        Task { try? await database.markOpened(showID: show.id) }
    }

    // MARK: - Playback

    func queuedTrack(_ item: EpisodeItem) -> QueuedTrack {
        QueuedTrack(
            trackID: item.episode.id,
            title: item.episode.title,
            artist: item.show.author.isEmpty ? item.show.title : item.show.author,
            albumTitle: item.show.title,
            albumID: nil,
            duration: item.episode.duration.map { .seconds($0) },
            podcast: PodcastMedia(audioURL: item.episode.audioURL, artworkURL: item.artworkURL)
        )
    }

    /// Plays an episode, followed by the rest of Up Next.
    func play(_ item: EpisodeItem, from seconds: Double? = nil) {
        if player.current?.trackID == item.id {
            if let seconds { player.seek(to: seconds) }
            if !player.isPlaying { player.resume() }
            return
        }
        let rest = ((try? database.queueNow()) ?? []).filter { $0.id != item.id }
        // The saved position is read when the item loads; a requested time wins over it.
        pendingStart = seconds.map { (item.id, $0) }
        player.play([queuedTrack(item)] + rest.map(queuedTrack))
        Task { try? await database.dequeue(episodeID: item.id) }
    }

    @ObservationIgnored private var pendingStart: (id: String, seconds: Double)?

    /// Where an episode should start (the player asks when it loads one).
    func resumePosition(for track: QueuedTrack) -> Double? {
        if let pending = pendingStart, pending.id == track.trackID {
            pendingStart = nil
            return pending.seconds
        }
        guard let item = try? database.episodeNow(id: track.trackID) else { return nil }
        return item.episode.isInProgress ? item.episode.position : nil
    }

    /// Saves progress from the player; handles finishing (auto-delete) and sync.
    func episodeProgress(_ track: QueuedTrack, position: Double, duration: Double) {
        let id = track.trackID
        Task {
            let finished = (try? await database.savePosition(episodeID: id, position: position, duration: duration)) ?? false
            if finished, deletePlayedDownloads, let item = try? database.episodeNow(id: id), !item.episode.isSaved,
               item.download != nil, player.current?.trackID != id {
                try? await downloads?.remove(episodeID: id)
            }
            schedulePush()
        }
    }

    /// The player moved to a new item: an episode that starts playing leaves Up Next, and
    /// picks up its show's speed.
    func playerChanged() {
        guard let track = player.current, track.isEpisode else { return }
        let id = track.trackID
        player.podcastRate = Float(rate(forEpisode: id))
        Task { try? await database.dequeue(episodeID: id) }
    }

    func rate(forEpisode id: String) -> Double {
        (try? database.episodeNow(id: id))?.show.playbackRate ?? defaultRate
    }

    /// Speed chosen in the player: updates the show's own speed if it has one, else the default.
    func setRate(_ rate: Float) {
        player.podcastRate = rate
        guard let id = player.current?.trackID, let item = try? database.episodeNow(id: id) else { return }
        if item.show.playbackRate != nil {
            updateShow(item.show) { $0.playbackRate = Double(rate) }
        } else {
            defaultRate = Double(rate)
        }
    }

    func playNext(_ item: EpisodeItem) {
        Task { try? await database.enqueue(episodeID: item.id, atFront: true) }
        if player.current?.isEpisode == true { player.playNext([queuedTrack(item)]) }
    }

    func playLast(_ item: EpisodeItem) {
        Task { try? await database.enqueue(episodeID: item.id, atFront: false) }
        if player.current?.isEpisode == true { player.addToQueue([queuedTrack(item)]) }
    }

    func removeFromUpNext(_ id: String) {
        Task { try? await database.dequeue(episodeID: id) }
    }

    /// Mirrors a reordered player queue (episodes only) to the stored Up Next.
    func syncQueueOrder() {
        guard player.current?.isEpisode == true else { return }
        let ids = player.queue.upNext.filter(\.isEpisode).map(\.trackID)
        Task { try? await database.setQueue(ids) }
    }

    // MARK: - Episode state

    func setPlayed(_ ids: [String], _ played: Bool) {
        Task {
            try? await database.setPlayed(episodeIDs: ids, played)
            if played, deletePlayedDownloads {
                for id in ids where player.current?.trackID != id {
                    if let item = try? database.episodeNow(id: id), item.download != nil, !item.episode.isSaved {
                        try? await downloads?.remove(episodeID: id)
                    }
                }
            }
            schedulePush()
        }
    }

    func markAllPlayed(_ show: ShowRecord) {
        Task {
            try? await database.markAllPlayed(showID: show.id)
            schedulePush()
        }
    }

    func setSaved(_ id: String, _ saved: Bool) {
        Task { try? await database.setSaved(episodeID: id, saved) }
    }

    // MARK: - Downloads

    func download(_ item: EpisodeItem) {
        let cellular = allowCellular
        Task { try? await downloads?.download(item.episode, automatic: false, allowCellular: cellular) }
        ImageCaching.prefetch([item.artworkURL].compactMap(\.self))
    }

    func removeDownload(_ id: String) {
        Task { try? await downloads?.remove(episodeID: id) }
    }

    func removeAllDownloads() {
        Task { try? await downloads?.removeAll() }
    }

    func localFile(episodeID: String) -> URL? {
        downloads?.localFile(episodeID: episodeID)
    }

    @ObservationIgnored private var chapterLoads: [String: Task<[Chapter], Never>] = [:]

    /// An episode's chapters (feed JSON, embedded in the audio, or timestamps in the show
    /// notes), loaded once per launch. The load is stored before its first `await`, so the
    /// episode page and the player asking at the same moment share one fetch, not two.
    func chapters(for episode: EpisodeRecord) async -> [Chapter] {
        if let load = chapterLoads[episode.id] { return await load.value }
        let audioURL = localFile(episodeID: episode.id) ?? episode.audioURL
        // Unstructured on purpose: a caller leaving (closing the player) shouldn't cancel the
        // fetch another screen is waiting on.
        let load = Task {
            await ChapterLoader.load(chaptersURL: episode.chaptersURL, audioURL: audioURL, notesHTML: episode.notesHTML, duration: episode.duration)
        }
        chapterLoads[episode.id] = load
        return await load.value
    }

    private func autoDownload() async {
        guard isEnabled, autoDownloadCount > 0, let ids = try? database.autoDownloadCandidates(perShow: autoDownloadCount) else { return }
        let cellular = allowCellular
        for item in (try? database.episodesNow(ids: ids)) ?? [] {
            try? await downloads?.download(item.episode, automatic: true, allowCellular: cellular)
        }
    }

    // MARK: - OPML

    /// Follows every show in an OPML file; returns how many were added.
    func importOPML(_ data: Data) async -> Int {
        let entries = OPML.parse(data)
        let existing = Set(((try? database.followedShowsNow()) ?? []).map(\.id))
        var added = 0
        await withTaskGroup(of: Bool.self) { group in
            var iterator = entries.filter { !existing.contains(PodcastID.show(feedURL: $0.feedURL)) }.makeIterator()
            for _ in 0 ..< 4 {
                guard let entry = iterator.next() else { break }
                group.addTask { (try? await self.fetcher.load(feedURL: entry.feedURL, follow: true)) != nil }
            }
            for await ok in group {
                if ok { added += 1 }
                if let entry = iterator.next() {
                    group.addTask { (try? await self.fetcher.load(feedURL: entry.feedURL, follow: true)) != nil }
                }
            }
        }
        if added > 0 { subscriptionsChanged() }
        return added
    }

    func exportOPML() -> String {
        OPML.export((try? database.followedShowsNow()) ?? [])
    }

    // MARK: - Removing data

    /// Unfollows everything and deletes progress, Up Next and downloads (keeps settings).
    func removeAllData() async {
        if player.current?.isEpisode == true { player.stop() }
        try? await downloads?.removeAll()
        _ = try? await database.pool.write { db in
            try ShowRecord.deleteAll(db)
        }
        subscriptionsChanged()
    }

    // MARK: - Background refresh

    /// For the background refresh task: refresh, auto-download and sync. Returns false on failure.
    func backgroundRefresh() async -> Bool {
        guard isEnabled else { return true }
        await refreshAll()
        await sync()
        return true
    }

    // MARK: - Sync (Jellyfin DisplayPreferences)

    private func subscriptionsChanged() {
        defaults.set(Date().timeIntervalSince1970, forKey: key("subsUpdated"))
        schedulePush()
    }

    private func schedulePush() {
        guard syncWithJellyfin else { return }
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await sync()
        }
    }

    private func localSyncState() -> PodcastSyncState {
        func date(_ name: String) -> Date? { (defaults.object(forKey: key(name)) as? Double).map(Date.init(timeIntervalSince1970:)) }
        var state = PodcastSyncState(
            enabled: isEnabled, enabledUpdated: date("enabledUpdated"),
            subscriptions: ((try? database.followedShowsNow()) ?? []).map(\.feedURL),
            subscriptionsUpdated: date("subsUpdated")
        )
        for episode in (try? database.listeningState()) ?? [] {
            if let played = episode.playedAt {
                state.played[episode.id] = played
            } else if episode.position > 0 {
                state.positions[episode.id] = .init(seconds: episode.position, updated: episode.lastPlayedAt ?? Date())
            }
        }
        return state
    }

    /// Pulls the server's copy, applies anything newer here, and pushes the merged result.
    func sync() async {
        guard syncWithJellyfin else { return }
        do {
            let remote = PodcastSyncState(customPrefs: try await library.customPreferences(id: PodcastSyncState.preferencesID))
            let local = localSyncState()
            let merged = local.merged(withRemote: remote)
            try await apply(merged, over: local)
            let pushed = merged.customPrefs
            if pushed != remote.customPrefs {
                try await library.saveCustomPreferences(pushed, id: PodcastSyncState.preferencesID)
            }
        } catch is CancellationError {
        } catch {
            log.error("Podcast sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ merged: PodcastSyncState, over local: PodcastSyncState) async throws {
        if merged.enabledUpdated != local.enabledUpdated, let enabled = merged.enabled {
            defaults.set(merged.enabledUpdated?.timeIntervalSince1970, forKey: key("enabledUpdated"))
            defaults.set(enabled, forKey: key("enabled"))
            if isEnabled != enabled {
                // Set the stored value directly so this doesn't count as a new local change.
                withMutation(keyPath: \.isEnabled) { _isEnabled = enabled }
            }
        }
        if merged.subscriptionsUpdated != local.subscriptionsUpdated {
            let have = Set(local.subscriptions.map { PodcastID.show(feedURL: $0) })
            let want = Set(merged.subscriptions.map { PodcastID.show(feedURL: $0) })
            for url in merged.subscriptions where !have.contains(PodcastID.show(feedURL: url)) {
                _ = try? await fetcher.load(feedURL: url, follow: true)
            }
            for url in local.subscriptions where !want.contains(PodcastID.show(feedURL: url)) {
                try? await database.setFollowed(showID: PodcastID.show(feedURL: url), false)
            }
            defaults.set(merged.subscriptionsUpdated?.timeIntervalSince1970, forKey: key("subsUpdated"))
        }
        let positions = merged.positions.filter { local.positions[$0.key] != $0.value }.mapValues { (position: $0.seconds, updated: $0.updated) }
        let played = merged.played.filter { local.played[$0.key] == nil }
        if !positions.isEmpty || !played.isEmpty {
            try await database.applyRemote(positions: positions, played: played)
        }
    }
}
