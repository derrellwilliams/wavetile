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

/// Online/offline state: whether the device has a network, and whether the Jellyfin server
/// answers on it (a LAN-only server is out of reach away from home, and remote access can be
/// down). Screens dim music that isn't downloaded while either is missing.
@Observable
final class Connectivity {
    /// One monitor for the app, started at launch so Siri and CarPlay see the real state at once.
    static let shared = Connectivity()

    struct Server: Equatable {
        let url: URL
        let id: String

        var isCleartext: Bool { url.scheme?.lowercased() == "http" }
    }

    private(set) var hasNetwork = true
    /// The current path costs money or is limited (cellular, hotspot, Low Data Mode): streams buffer less.
    private(set) var isMetered = false
    /// Whether the server answered its last check. Optimistic until a check says otherwise, so
    /// launch doesn't dim the library while the first check runs.
    private(set) var serverReachable = true
    /// Music can stream: the network is up and the server answers.
    var isOnline: Bool { hasNetwork && serverReachable }

    /// The signed-in server; nil when signed out (nothing to check).
    var server: Server? {
        didSet {
            guard server != oldValue else { return }
            pathDebounce?.cancel()
            pathDebounce = nil
            if let server { ServerIdentity.shared.register(server.url, serverID: server.id) }
            // An HTTP server gets no requests until it proves itself (`ServerIdentity`), so it starts
            // offline rather than offering streams that can't start yet. On the LAN that's milliseconds.
            serverReachable = server?.isCleartext != true
            check(grace: false)
        }
    }

    /// Called when the device changes networks, before the server is checked again. `strict` is
    /// false for an update that kept the same interfaces (see `AudioPlayer.networkChanged`).
    @ObservationIgnored var onNetworkChange: ((_ strict: Bool) async -> Void)?

    /// Called when the app returns to the foreground, where no network change was seen.
    @ObservationIgnored var onForeground: (() async -> Void)?

    @ObservationIgnored private let monitor = NWPathMonitor()
    /// Which interfaces the last path used: Wi-Fi to cellular stays "connected" but can put a
    /// LAN-only server out of reach, so any change means checking again.
    @ObservationIgnored private var interfaces: [String] = []
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// Which step of the backoff the pending retry is on.
    @ObservationIgnored private var retryAttempt = 0
    @ObservationIgnored private var lastProbe = ContinuousClock.now
    /// Waits out a burst of same-interface updates so they cost one check, not one each.
    @ObservationIgnored private var pathDebounce: Task<Void, Never>?
    @ObservationIgnored private var foregroundToken: NSObjectProtocol?

    init() {
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

    /// Pings the server now and returns once `serverReachable` has the answer (a stream just
    /// failed to connect: one bad stream shouldn't dim the library on its own).
    func recheck() async { await recheck(attempt: 0, grace: false) }

    /// `grace` gives the first miss after a good answer one quiet retry before the server counts as
    /// unreachable (Wi-Fi still waking after foreground). A real network change or a failed stream
    /// has no grace: the miss is believed at once.
    private func recheck(attempt: Int, grace: Bool) async {
        guard hasNetwork, let server else { return }
        lastProbe = .now
        var reachable = await ServerIdentity.shared.probe(server.url)
        // A network change mid-check (Wi-Fi waking, roaming) voids the answer: ask again.
        var stale = 0
        while reachable == nil, stale < 3, !Task.isCancelled {
            stale += 1
            reachable = await ServerIdentity.shared.probe(server.url)
        }
        guard !Task.isCancelled, server == self.server, hasNetwork else { return }
        // Still voided after three asks (path updates keep landing): look again soon, as if this
        // one hadn't happened. Returning would end the retry chain and leave the last answer standing.
        guard let reachable else { scheduleRetry(attempt: attempt, grace: grace); return }
        if reachable {
            serverReachable = true
            // May be this very retry's task: it has nothing left to await, so cancelling it is harmless.
            retryTask?.cancel()
            return
        }
        if grace, attempt == 0, serverReachable {
            scheduleRetry(attempt: 1, grace: false)
        } else {
            serverReachable = false
            scheduleRetry(attempt: attempt + 1, grace: false)
        }
    }

    /// Looks again after 1, 2, 4 and 8 s, then every 15 s, so the library comes back on its own.
    private func scheduleRetry(attempt: Int, grace: Bool) {
        retryTask?.cancel()
        retryAttempt = attempt
        let delay: Duration = attempt <= 4 ? .seconds(1 << max(attempt - 1, 0)) : .seconds(15)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.recheck(attempt: attempt, grace: grace)
        }
    }

    /// Same-interface chatter while the server is out of reach brings the next look forward
    /// without resetting the backoff, and at most once every 2 s.
    private func retryNow() {
        guard ContinuousClock.now - lastProbe >= .seconds(2) else { return }
        retryTask?.cancel()
        let attempt = max(retryAttempt, 1)
        retryTask = Task { [weak self] in await self?.recheck(attempt: attempt, grace: false) }
    }

    /// How long a burst of same-interface updates is collected before the server is checked. A
    /// fixed deadline from the first update, so steady chatter can't postpone the check.
    private static let sameInterfaceDelay: Duration = .milliseconds(500)

    private func pathChanged(online: Bool, interfaces: [String]) {
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
            // A real change: no waiting, and any pending same-interface check is superseded.
            pathDebounce?.cancel()
            pathDebounce = nil
            if cleartext { announceNetworkChange(strict: true) }
            check(grace: false)
        } else if !cleartext {
            // HTTPS, unreachable: no identity to re-prove, so keep the backoff and look sooner.
            retryNow()
        } else if pathDebounce == nil {
            // Same interfaces: the player keeps its streams while the server proves itself again.
            pathDebounce = Task { [weak self] in
                try? await Task.sleep(for: Self.sameInterfaceDelay)
                guard !Task.isCancelled, let self else { return }
                pathDebounce = nil
                announceNetworkChange(strict: false)
                check(grace: true)
            }
        }
    }

    private func announceNetworkChange(strict: Bool) {
        ServerIdentity.shared.networkChanged()
        if let onNetworkChange { Task { await onNetworkChange(strict) } }
    }

    /// Security: no path update arrives while the app is suspended, and the one for a network
    /// joined meanwhile can land after the first requests. An HTTP server proves itself again
    /// before any of them carries the token.
    private func enteredForeground() {
        // This check covers whatever a pending same-interface one would have done.
        pathDebounce?.cancel()
        pathDebounce = nil
        if server?.isCleartext == true {
            ServerIdentity.shared.networkChanged()
            if let onForeground { Task { await onForeground() } }
        }
        check(grace: true)
    }

    private func check(grace: Bool) {
        checkTask?.cancel()
        retryTask?.cancel()
        checkTask = Task { await recheck(attempt: 0, grace: grace) }
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
    /// Albums, playlists and collections with something downloaded, for offline dimming.
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
