import DesignSystem
import Foundation
import GRDB
import JellyfinKit
import Library
import Observation
import Persistence
import Playback

/// The signed-in user's library: local database, background sync, and API access.
/// Screens read from the database (instant, offline) and observe it for live updates.
@Observable
final class LibraryStore {
    let database: LibraryDatabase
    let api: LibraryClient
    let editor: LibraryEditor
    private let sync: LibrarySync

    private(set) var progress: LibrarySync.Progress?
    private(set) var isSyncing = false
    private(set) var syncError: String?
    private(set) var hasSyncedOnce = false
    /// Runs after each successful sync (downloaded-playlist refresh).
    @ObservationIgnored var afterSync: (() async -> Void)?

    init(session: ServerSession, token: String, auth: AuthService, database: LibraryDatabase) {
        self.database = database
        self.api = LibraryClient(session: session, token: token, auth: auth)
        let sync = LibrarySync(session: session, token: token, auth: auth, database: database)
        self.sync = sync
        self.editor = LibraryEditor(session: session, token: token, auth: auth, database: database, sync: sync)
        self.hasSyncedOnce = (try? database.syncState()?.lastCompleted) != nil
    }

    func syncIfNeeded() async {
        guard (try? await sync.needsSync()) ?? true else { return }
        await syncNow()
    }

    func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        defer {
            isSyncing = false
            progress = nil
        }
        do {
            try await sync.run { [weak self] progress in
                Task { @MainActor in self?.progress = progress }
            }
            hasSyncedOnce = true
            await afterSync?()
        } catch is CancellationError {
        } catch {
            syncError = "Library sync failed. Pull to retry."
        }
    }

    /// Live stream of a query's results; ends when the observing task is cancelled.
    func observe<T: Sendable>(_ observation: ValueObservation<ValueReducers.Fetch<T>>) -> AsyncValueObservation<T> {
        observation.values(in: database.pool)
    }

    // MARK: Artwork

    /// Art for anything in the play queue: the album for songs, the episode or show for podcasts.
    func artwork(for track: QueuedTrack?, maxPixelWidth: Int) -> ArtworkSource {
        if let podcast = track?.podcast { return .unsized(podcast.artworkURL, maxPixelWidth: maxPixelWidth) }
        return artwork(itemID: track?.albumID, tag: track?.albumImageTag, maxPixelWidth: maxPixelWidth)
    }

    /// Album or track-album art. `maxPixelWidth` should match the rendered size × scale.
    func artwork(itemID: String?, tag: String? = nil, maxPixelWidth: Int) -> ArtworkSource {
        guard let itemID else { return .placeholder(seed: 0) }
        return .url(api.imageURL(itemID: itemID, tag: tag, maxPixelWidth: maxPixelWidth))
    }

    var statusText: String? {
        guard let progress else { return nil }
        let count = progress.total.map { "\(progress.completed.formatted()) of \($0.formatted())" } ?? progress.completed.formatted()
        return switch progress.phase {
        case .artists: "Syncing artists… \(count)"
        case .albums: "Syncing albums… \(count)"
        case .tracks: "Syncing songs… \(count)"
        case .playlists: "Syncing playlists…"
        case .collections: "Syncing collections…"
        case .finishing: "Finishing up…"
        }
    }
}
