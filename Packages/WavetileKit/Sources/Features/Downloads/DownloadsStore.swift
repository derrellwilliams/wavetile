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
    }

    private(set) var hasNetwork = true
    /// Whether the server answered its last check. Optimistic until a check says otherwise, so
    /// launch doesn't dim the library while the first check runs.
    private(set) var serverReachable = true
    /// Music can stream: the network is up and the server answers.
    var isOnline: Bool { hasNetwork && serverReachable }

    /// The signed-in server; nil when signed out (nothing to check).
    var server: Server? {
        didSet {
            guard server != oldValue else { return }
            serverReachable = true
            check()
        }
    }

    @ObservationIgnored private let monitor = NWPathMonitor()
    /// Which interfaces the last path used: Wi-Fi to cellular stays "connected" but can put a
    /// LAN-only server out of reach, so any change means checking again.
    @ObservationIgnored private var interfaces: [String] = []
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var foregroundToken: NSObjectProtocol?
    /// Short timeout and no waiting for a network: the answer is needed now, not eventually.
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let interfaces = path.availableInterfaces.map(\.name)
            Task { @MainActor in self?.pathChanged(online: online, interfaces: interfaces) }
        }
        monitor.start(queue: DispatchQueue(label: "com.derrellwilliams.wavetile.connectivity"))
        // Coming back to the app is when a listener has likely moved (left home, arrived back).
        foregroundToken = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    deinit {
        monitor.cancel()
        checkTask?.cancel()
        retryTask?.cancel()
    }

    /// Pings the server now and returns once `serverReachable` has the answer (a stream just
    /// failed to connect: one bad stream shouldn't dim the library on its own).
    func recheck() async {
        guard hasNetwork, let server else { return }
        let reachable = await Self.ping(server, session: session)
        guard !Task.isCancelled, server == self.server, hasNetwork else { return }
        serverReachable = reachable
        retryTask?.cancel()
        // While it doesn't answer, try again every 30 s so the library comes back on its own.
        guard !reachable else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await self?.recheck()
        }
    }

    private func pathChanged(online: Bool, interfaces: [String]) {
        guard online != hasNetwork || interfaces != self.interfaces else { return }
        hasNetwork = online
        self.interfaces = interfaces
        check()
    }

    private func check() {
        checkTask?.cancel()
        retryTask?.cancel()
        checkTask = Task { await recheck() }
    }

    /// Security: Jellyfin's public info endpoint, sent without the token. Only this server
    /// answering counts: a captive portal or another host at the same LAN address returns a
    /// page, not this server's ID.
    @concurrent private nonisolated static func ping(_ server: Server, session: URLSession) async -> Bool {
        struct PublicInfo: Decodable {
            let Id: String?
        }
        let url = server.url.appending(path: "System/Info/Public")
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let id = (try? JSONDecoder().decode(PublicInfo.self, from: data))?.Id
        else { return false }
        // A session saved without an ID can't be matched; any Jellyfin answer has to do.
        guard !server.id.isEmpty else { return true }
        let normalized = { (id: String) in id.lowercased().replacingOccurrences(of: "-", with: "") }
        return normalized(id) == normalized(server.id)
    }
}

/// UI-facing downloads: settings, live status, and actions.
@Observable
final class DownloadsStore {
    let manager: DownloadManager?
    private let database: LibraryDatabase
    private let library: LibraryStore

    /// Fully downloaded track IDs (row badges, offline availability).
    private(set) var downloadedTrackIDs: Set<String> = []
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
        self.manager = try? DownloadManager(serverID: session.serverID, userID: session.userID, database: library.database, library: library.api)
        self.quality = UserDefaults.standard.string(forKey: "downloadQuality").flatMap(DownloadManager.Quality.init) ?? .high
        self.allowCellular = UserDefaults.standard.object(forKey: "downloadOverCellular") as? Bool ?? false
        // Read now so offline checks are right before `observe()` runs (and in CarPlay, where it may not).
        self.downloadedTrackIDs = (try? library.database.downloadedTrackIDsNow()) ?? []
    }

    /// Long-running: keeps `downloadedTrackIDs` and `totalBytes` live. Run from a view `.task`.
    func observe() async {
        async let ids: Void = observeTrackIDs()
        async let bytes: Void = observeBytes()
        async let resume: Void = resumePending()
        _ = await (ids, bytes, resume)
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

    private func resumePending() async {
        await manager?.resumePending(quality: quality, allowCellular: allowCellular)
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

    func remove(collectionID: String) {
        Task { try? await manager?.remove(collectionID: collectionID) }
    }

    func removeAll() {
        Task { try? await manager?.removeAll() }
    }

    /// After a library sync: pull new tracks into downloaded playlists.
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

    /// Lock Screen / Dynamic Island progress for one collection's download.
    private func trackWithLiveActivity(_ record: DownloadCollectionRecord) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let status = try? database.downloadStatusNow(collectionID: record.id),
              status.isInProgress
        else { return }
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
