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
    /// How many times each playlist or collection's generated cover has been shuffled, by item
    /// ID. Kept on this device; an item that's never been shuffled has the same cover everywhere.
    private(set) var coverShuffles: [String: Int] = UserDefaults.standard.dictionary(forKey: LibraryStore.coverShufflesKey) as? [String: Int] ?? [:]
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
        // Send plays from offline listening first, so the sync pulls counts that include them.
        await reportPendingPlays()
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

    /// Sends plays recorded offline, oldest first; stops at the first failure (still offline)
    /// and tries again on the next sync.
    func reportPendingPlays() async {
        guard let plays = try? await database.pendingPlays() else { return }
        for play in plays {
            guard let id = play.id, await api.markPlayed(trackID: play.trackID, at: play.playedAt) else { return }
            try? await database.removePendingPlay(id: id)
        }
    }

    /// Live stream of a query's results; ends when the observing task is cancelled.
    func observe<T: Sendable>(_ observation: ValueObservation<ValueReducers.Fetch<T>>) -> AsyncValueObservation<T> {
        observation.values(in: database.pool)
    }

    /// Skips results equal to the last one, so writes that don't change what a screen shows
    /// (another table's rows, a no-op sync page) don't re-render it.
    func observe<T: Sendable & Equatable>(_ observation: ValueObservation<ValueReducers.Fetch<T>>) -> AsyncValueObservation<T> {
        observation.removeDuplicates().values(in: database.pool)
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

    /// A playlist or collection's cover: its server image when it has one (uploaded, or made by
    /// Jellyfin), otherwise a generated one (`CoverArt`) as a unique placeholder.
    func cover(for itemID: String, tag: String?, maxPixelWidth: Int) -> ArtworkSource {
        guard tag == nil else { return artwork(itemID: itemID, tag: tag, maxPixelWidth: maxPixelWidth) }
        return .generated(seed: coverSeed(for: itemID))
    }

    func coverSeed(for itemID: String) -> String {
        CoverArt.seed(id: itemID, shuffle: coverShuffles[itemID] ?? 0)
    }

    /// Swaps an item's cover for the next one its seed gives.
    func shuffleCover(for itemID: String) {
        coverShuffles[itemID, default: 0] += 1
        UserDefaults.standard.set(coverShuffles, forKey: Self.coverShufflesKey)
    }

    /// Keeps a shuffled cover's count when an item gets a new ID (a collection renamed by
    /// recreating it). Its cover still changes, since the ID is part of the seed.
    func moveCoverShuffle(from oldID: String, to newID: String) {
        guard let count = coverShuffles.removeValue(forKey: oldID) else { return }
        coverShuffles[newID] = count
        UserDefaults.standard.set(coverShuffles, forKey: Self.coverShufflesKey)
    }

    private static let coverShufflesKey = "coverShuffles"

    /// Whether the account is a server admin. Only admins can change item images, so Upload and
    /// Remove Cover Image show only for them. Checked once per session.
    private(set) var isAdmin = false

    func loadPermissions() async {
        isAdmin = (try? await api.isAdministrator()) ?? false
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
