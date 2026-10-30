import ActivityKit
import DesignSystem
import Downloads
import Foundation
import JellyfinKit
import Network
import Observation
import Persistence
import WidgetShared

/// Online/offline state. Screens dim music that isn't downloaded while offline.
@Observable
final class Connectivity {
    /// One monitor for the app, started at launch so Siri and CarPlay see the real state at once.
    static let shared = Connectivity()

    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "com.derrellwilliams.wavetile.connectivity"))
    }

    deinit { monitor.cancel() }
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
