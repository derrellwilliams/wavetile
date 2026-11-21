import ActivityKit
import DesignSystem
import Downloads
import Foundation
import JellyfinKit
import Network
import Observation
import Persistence
import UIKit
import WidgetShared

/// Online/offline state, from two signals that can't guess wrong:
/// - `hasNetwork`: whether iOS has a usable path. Without one, screens dim music that isn't
///   downloaded and say so.
/// - `serverReachable`: false only after a real request to the server failed (an API call, a
///   stream, an identity check; see `ServerIdentity.observeReachability`) and a probe a second
///   later failed too, so one slow page or Wi-Fi blip doesn't count. True again at its next answer. It shows "Can't reach your server" and keeps streams from starting, but never dims
///   the library: when dimming followed a guess about the server, a wrong guess dimmed everything.
/// While the server is unreachable it's looked at again every few seconds, so the notice clears
/// by itself.
@Observable
final class Connectivity {
    /// One monitor for the app, started at launch so Siri and CarPlay see the real state at once.
    static let shared = Connectivity()

    struct Server: Equatable {
        let url: URL
        let id: String

        var isCleartext: Bool { url.scheme?.lowercased() == "http" }

        /// `other` goes to this server (same scheme, host and port).
        func isSameOrigin(_ other: URL) -> Bool { ServerIdentity.isSameOrigin(url, other) }
    }

    private(set) var hasNetwork = true
    /// The current path costs money or is limited (cellular, hotspot, Low Data Mode): streams buffer less.
    private(set) var isMetered = false
    /// The server answered its last request, or nothing has been asked of it yet.
    private(set) var serverReachable = true
    /// Music can stream: the network is up and the server hasn't failed a request.
    var isOnline: Bool { hasNetwork && serverReachable }

    /// The signed-in server; nil when signed out (nothing to check).
    var server: Server? {
        didSet {
            guard server != oldValue else { return }
            pathDebounce?.cancel()
            pathDebounce = nil
            checkTask?.cancel()
            checkTask = nil
            retryTask?.cancel()
            retryAttempt = 0
            if let server { ServerIdentity.shared.register(server.url, serverID: server.id) }
            serverReachable = true
        }
    }

    /// Called when the device changes networks. `strict` is false for an update that kept the
    /// same interfaces (see `AudioPlayer.networkChanged`).
    @ObservationIgnored var onNetworkChange: ((_ strict: Bool) async -> Void)?

    /// Called when the app returns to the foreground, where no network change was seen.
    @ObservationIgnored var onForeground: (() async -> Void)?

    @ObservationIgnored private let monitor = NWPathMonitor()
    /// Which interfaces the last path used: Wi-Fi to cellular stays "connected" but is a new network.
    @ObservationIgnored private var interfaces: [String] = []
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// Which step of the backoff the pending retry is on, so extra looks (path updates, foreground)
    /// don't restart it.
    @ObservationIgnored private var retryAttempt = 0
    @ObservationIgnored private var lastProbe = ContinuousClock.now
    /// Waits out a burst of same-interface updates so they cost one re-verification, not one each.
    @ObservationIgnored private var pathDebounce: Task<Void, Never>?
    @ObservationIgnored private var foregroundToken: NSObjectProtocol?

    @ObservationIgnored private let probe: (URL) async -> Bool?
    @ObservationIgnored private let wait: (Duration) async throws -> Void

    /// The injected probe and clock let connectivity transitions be tested without a live network.
    init(
        server: Server? = nil,
        monitorsNetwork: Bool = true,
        probe: @escaping (URL) async -> Bool? = { await ServerIdentity.shared.probe($0) },
        wait: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.server = server
        self.probe = probe
        self.wait = wait
        if let server { ServerIdentity.shared.register(server.url, serverID: server.id) }
        guard monitorsNetwork else { return }
        ServerIdentity.shared.observeReachability { [weak self] url, reachable in
            Task { @MainActor in self?.report(url, reachable: reachable) }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let interfaces = path.availableInterfaces.map(\.name)
            let metered = path.isExpensive || path.isConstrained
            Task { @MainActor in
                self?.isMetered = metered
                self?.pathChanged(online: online, interfaces: interfaces)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.derrellwilliams.wavetile.connectivity"))
        // Coming back to the app is when a listener has likely moved (left home, arrived back).
        foregroundToken = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enteredForeground() }
        }
    }

    deinit {
        monitor.cancel()
        checkTask?.cancel()
        retryTask?.cancel()
        pathDebounce?.cancel()
    }

    /// A request to `url` got an answer from the server, or couldn't reach it. Only the signed-in
    /// server counts, and a failure with no network is already said by the offline notice. A
    /// failure is confirmed by a probe before anything changes (a report still in flight from a
    /// previous server at the same address only costs that probe).
    func report(_ url: URL, reachable: Bool) {
        guard let server, server.isSameOrigin(url) else { return }
        if reachable {
            // An answer also voids a confirmation probe still running.
            if !serverReachable || checkTask != nil { markReachable() }
        } else if hasNetwork, serverReachable, checkTask == nil {
            check()
        }
    }

    /// Asks the server now (a failed stream, the notice's Retry) and returns once the answer is
    /// in. All callers share the current check.
    func recheck() async {
        if checkTask == nil { check() }
        await checkTask?.value
    }

    func pathChanged(online: Bool, interfaces: [String]) {
        // Security: an HTTP server's address can be another machine on the new network (café Wi-Fi
        // on the same subnet), and Wi-Fi to Wi-Fi keeps the same interfaces, so any path update
        // means it proves itself again before it gets the token.
        let cleartext = server?.isCleartext == true
        let changed = online != hasNetwork || interfaces != self.interfaces
        // While the server is out of reach, any update is a reason to look again: Wi-Fi settling
        // often shows up as same-interface chatter.
        let unreachable = !serverReachable && online
        guard cleartext || changed || unreachable else { return }
        hasNetwork = online
        self.interfaces = interfaces

        if changed {
            // A real change: no waiting, and any pending same-interface work is superseded.
            pathDebounce?.cancel()
            pathDebounce = nil
            if cleartext { announceNetworkChange(strict: true) }
            if !online {
                checkTask?.cancel()
                checkTask = nil
                retryTask?.cancel()
            } else if !serverReachable {
                // Maybe back in reach (home Wi-Fi again): look now rather than at the next retry.
                check(attempt: retryAttempt)
            }
            return
        }
        // Same interfaces. Security first: an HTTP server proves itself again whatever its state.
        if cleartext, pathDebounce == nil {
            // The player keeps its streams while the server proves itself again.
            pathDebounce = Task { [weak self] in
                try? await Task.sleep(for: Self.sameInterfaceDelay)
                guard !Task.isCancelled, let self else { return }
                pathDebounce = nil
                announceNetworkChange(strict: false)
            }
        }
        // At most every 2 s, without resetting the backoff.
        if unreachable, ContinuousClock.now - lastProbe >= .seconds(2) { check(attempt: retryAttempt) }
    }

    /// How long a burst of same-interface updates is collected. A fixed deadline from the first
    /// update, so steady chatter can't postpone it.
    private static let sameInterfaceDelay: Duration = .milliseconds(500)

    private func announceNetworkChange(strict: Bool) {
        ServerIdentity.shared.networkChanged()
        if let onNetworkChange { Task { await onNetworkChange(strict) } }
    }

    /// Security: no path update arrives while the app is suspended, and the one for a network
    /// joined meanwhile can land after the first requests. An HTTP server proves itself again
    /// before any of them carries the token.
    private func enteredForeground() {
        pathDebounce?.cancel()
        pathDebounce = nil
        if server?.isCleartext == true {
            ServerIdentity.shared.networkChanged()
            if let onForeground { Task { await onForeground() } }
        }
        if hasNetwork, !serverReachable { check(attempt: retryAttempt) }
    }

    /// Also stops a probe still running, so its late miss can't undo this answer.
    private func markReachable() {
        serverReachable = true
        retryAttempt = 0
        retryTask?.cancel()
        retryTask = nil
        checkTask?.cancel()
        checkTask = nil
    }

    private func check(attempt: Int = 0) {
        checkTask?.cancel()
        retryTask?.cancel()
        checkTask = Task {
            await probeServer(attempt: attempt)
            if !Task.isCancelled { checkTask = nil }
        }
    }

    private func probeServer(attempt: Int) async {
        guard hasNetwork, let server else { return }
        lastProbe = .now
        var answer = await probe(server.url)
        // A network change mid-check (Wi-Fi waking, roaming) voids the answer: ask again.
        var stale = 0
        while answer == nil, stale < 3, !Task.isCancelled {
            stale += 1
            answer = await probe(server.url)
        }
        guard !Task.isCancelled, server == self.server, hasNetwork else { return }
        if answer == false, serverReachable {
            // One miss isn't an outage (a slow page, a Wi-Fi blip): ask once more a second later.
            do { try await wait(.seconds(1)) } catch { return }
            guard !Task.isCancelled, server == self.server, hasNetwork else { return }
            answer = await probe(server.url)
            guard !Task.isCancelled, server == self.server, hasNetwork else { return }
        }
        if answer == true {
            markReachable()
            return
        }
        // No answer at all leaves the last one standing; a confirmed miss marks it unreachable.
        if answer == false { serverReachable = false }
        if !serverReachable { scheduleRetry(attempt: attempt + 1) }
    }

    /// While unreachable: look again after 2 s, then every 5 s for a minute, then every 30 s.
    /// Coming back in reach by another route (home Wi-Fi) is a path update, which looks at once.
    private func scheduleRetry(attempt: Int) {
        retryTask?.cancel()
        retryAttempt = attempt
        let delay: Duration = attempt <= 1 ? .seconds(2) : attempt <= 13 ? .seconds(5) : .seconds(30)
        retryTask = Task { [weak self] in
            do { try await self?.wait(delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.check(attempt: attempt)
        }
    }
}

/// UI-facing downloads: settings, live status, and actions.
@Observable
final class DownloadsStore {
    let manager: DownloadManager?
    private let database: LibraryDatabase
    private let library: LibraryStore
    /// Collections with a Live Activity this process is updating.
    @ObservationIgnored private var trackedActivities: Set<String> = []

    /// Fully downloaded track IDs (row badges, offline availability).
    private(set) var downloadedTrackIDs: Set<String> = []
    /// Albums, playlists and collections with something downloaded: their download mark, and
    /// what stays undimmed with no network.
    private(set) var available = OfflineAvailability()
    private(set) var totalBytes: Int64 = 0

    var quality: DownloadManager.Quality {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "downloadQuality") }
    }

    var allowCellular: Bool {
        didSet { UserDefaults.standard.set(allowCellular, forKey: "downloadOverCellular") }
    }

    init(session: ServerSession, library: LibraryStore) {
        self.library = library
        self.database = library.database
        // With a stand-in database no finished file would match a row, and the manager deletes those.
        self.manager = library.database.isTemporary ? nil : try? DownloadManager(serverID: session.serverID, userID: session.userID, database: library.database, library: library.api)
        self.quality = UserDefaults.standard.string(forKey: "downloadQuality").flatMap(DownloadManager.Quality.init) ?? .high
        self.allowCellular = UserDefaults.standard.object(forKey: "downloadOverCellular") as? Bool ?? false
        // Read now so offline checks are right before `observe()` runs (and in CarPlay, where it may not).
        self.downloadedTrackIDs = (try? library.database.downloadedTrackIDsNow()) ?? []
    }

    /// Long-running: keeps `downloadedTrackIDs`, `available` and `totalBytes` live. Run from a view `.task`.
    func observe() async {
        async let ids: Void = observeTrackIDs()
        async let bytes: Void = observeBytes()
        async let resume: Void = recoverPending()
        async let availability: Void = observeAvailability()
        async let favorites: Void = observeFavoritesDownload()
        async let activities: Void = resumeLiveActivities()
        _ = await (ids, bytes, resume, availability, favorites, activities)
    }

    /// Hearting or unhearting updates the Favorites download now, not at the next library sync.
    private func observeFavoritesDownload() async {
        await library.observe(database.favoritesDownloadTracks()) { tracks in
            guard tracks != nil else { return }
            let quality = quality, cellular = allowCellular
            Task { await manager?.syncFavorites(quality: quality, allowCellular: cellular) }
        }
    }

    private func observeAvailability() async {
        await library.observe(database.offlineAvailability()) { available = $0 }
    }

    private func observeTrackIDs() async {
        do {
            for try await ids in library.observe(database.downloadedTrackIDs()) { downloadedTrackIDs = ids }
        } catch { Log.observationFailed(error) }
    }

    private func observeBytes() async {
        do {
            for try await bytes in library.observe(database.totalDownloadedBytes()) { totalBytes = bytes }
        } catch { Log.observationFailed(error) }
    }

    /// Reconcile stranded tasks while this store is observed, including after server recovery.
    private func recoverPending() async {
        await resumePending()
        while !Task.isCancelled {
            await manager?.resumePending(quality: quality, allowCellular: allowCellular, retryFailed: false)
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }

    func pause(collectionID: String) async throws {
        try await manager?.pause(collectionID: collectionID)
    }

    func resume(collectionID: String) async throws {
        try await manager?.resume(collectionID: collectionID, quality: quality, allowCellular: allowCellular)
    }

    private func resumePending() async {
        await manager?.resumePending(quality: quality, allowCellular: allowCellular)
    }

    /// Transfers from an HTTP server stop on a network change and restart once it has proved itself.
    func networkChanged() async {
        await manager?.networkChanged()
        await resumePending()
    }

    func isDownloaded(_ trackID: String) -> Bool { downloadedTrackIDs.contains(trackID) }

    func download(album: AlbumSummary, trackIDs: [String]) {
        let record = DownloadCollectionRecord(id: album.id, kind: .album, name: album.title, subtitle: album.artist, imageTag: album.imageTag)
        start(record, trackIDs: trackIDs)
        prefetchArtwork(itemID: album.id, tag: album.imageTag)
    }

    func download(playlist: PlaylistRecord, trackIDs: [String], albumIDs: [String]) {
        let record = DownloadCollectionRecord(id: playlist.id, kind: .playlist, name: playlist.name, subtitle: "Playlist", imageTag: playlist.imageTag)
        start(record, trackIDs: trackIDs)
        prefetchArtwork(itemID: playlist.id, tag: playlist.imageTag)
        for albumID in Set(albumIDs) { prefetchArtwork(itemID: albumID, tag: nil) }
    }

    func download(collection: CollectionRecord, trackIDs: [String], albumIDs: [String]) {
        let record = DownloadCollectionRecord(id: collection.id, kind: .collection, name: collection.name, subtitle: "Collection", imageTag: collection.imageTag)
        start(record, trackIDs: trackIDs)
        prefetchArtwork(itemID: collection.id, tag: collection.imageTag)
        for albumID in Set(albumIDs) { prefetchArtwork(itemID: albumID, tag: nil) }
    }

    /// Favorite songs and the songs on favorite albums, as one download that updates as soon as a
    /// heart changes (`observeFavoritesDownload`).
    func downloadFavorites(trackIDs: [String], albumIDs: [String]) {
        let record = DownloadCollectionRecord(id: DownloadCollectionRecord.favoritesID, kind: .favorites, name: "Favorites", subtitle: "Favorites", imageTag: nil)
        start(record, trackIDs: trackIDs)
        for albumID in Set(albumIDs) { prefetchArtwork(itemID: albumID, tag: nil) }
    }

    func remove(collectionID: String) {
        Task { try? await manager?.remove(collectionID: collectionID) }
    }

    func removeAll() {
        Task { try? await manager?.removeAll() }
    }

    /// After a library sync: bring downloaded playlists, collections and Favorites up to date.
    func syncPlaylists() async {
        await manager?.syncPlaylists(quality: quality, allowCellular: allowCellular)
    }

    func localFile(trackID: String) -> URL? {
        manager?.localFile(trackID: trackID)
    }

    private func start(_ record: DownloadCollectionRecord, trackIDs: [String]) {
        let quality = quality, cellular = allowCellular
        Task {
            try? await manager?.download(record, trackIDs: trackIDs, quality: quality, allowCellular: cellular)
            await trackWithLiveActivity(record)
        }
    }

    /// Live Activities an earlier process left behind (the app was killed or suspended mid-download)
    /// have nothing updating them, so they'd show frozen progress for hours: end them, then
    /// pick up the downloads still running.
    private func resumeLiveActivities() async {
        for activity in Activity<DownloadActivityAttributes>.activities where !trackedActivities.contains(activity.attributes.collectionID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for collection in (try? database.allDownloadCollections()) ?? [] {
            Task { await trackWithLiveActivity(collection) }
        }
    }

    /// Sign-out: nothing of this account stays on the Lock Screen.
    static func endAllLiveActivities() async {
        for activity in Activity<DownloadActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Lock Screen / Dynamic Island progress for one collection's download. One activity per
    /// collection: asking again while it runs (Retry, a second tap) keeps the one that's updating.
    private func trackWithLiveActivity(_ record: DownloadCollectionRecord) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let status = try? database.downloadStatusNow(collectionID: record.id),
              status.isInProgress,
              trackedActivities.insert(record.id).inserted
        else { return }
        defer { trackedActivities.remove(record.id) }
        let attributes = DownloadActivityAttributes(collectionID: record.id, name: record.name, subtitle: record.subtitle)
        let initial = DownloadActivityAttributes.ContentState(done: status.done, total: status.total, progress: status.progress)
        guard let activity = try? Activity.request(attributes: attributes, content: .init(state: initial, staleDate: nil)) else { return }

        // Progress writes land many times a second; ActivityKit throttles updates and each one
        // costs battery, so send one when a track finishes or every 2 s otherwise.
        var lastDone = status.done
        var lastUpdate = ContinuousClock.now
        do {
            for try await status in library.observe(database.downloadStatus(collectionID: record.id)) {
                let state = DownloadActivityAttributes.ContentState(done: status.done, total: status.total, progress: status.progress)
                if !status.isRequested || !status.isInProgress {
                    // Finished, failed, or removed: show the final state briefly, then dismiss.
                    await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 60))
                    return
                }
                guard status.done != lastDone || ContinuousClock.now - lastUpdate >= .seconds(2) else { continue }
                lastDone = status.done
                lastUpdate = .now
                await activity.update(.init(state: state, staleDate: nil))
            }
        } catch {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Cache the artwork sizes the app renders so downloaded music looks right offline.
    private func prefetchArtwork(itemID: String, tag: String?) {
        let urls = [144, 480, 1320].compactMap { library.api.imageURL(itemID: itemID, tag: tag, maxPixelWidth: $0) }
        ImageCaching.prefetch(urls)
    }
}
