import DesignSystem
import Foundation
import GRDB
import JellyfinKit
import Library
import Observation
import Persistence
import Playback
import SwiftUI

/// The signed-in user's library: local database, background sync, and API access.
/// Screens read from the database (instant, offline) and observe it for live updates.
@Observable
final class LibraryStore {
    let database: LibraryDatabase
    let api: LibraryClient
    let editor: LibraryEditor
    private let sync: LibrarySync
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    /// Set at sign-out; work that finishes after it must not start anything (playback, writes).
    private(set) var shuttingDown = false

    private(set) var progress: LibrarySync.Progress?
    private(set) var isSyncing = false
    private(set) var syncError: String?
    private(set) var hasSyncedOnce = false
    /// How many times each playlist or collection's generated cover has been shuffled, by item
    /// ID. Kept on this device per server and account; an item that's never been shuffled has the
    /// same cover everywhere. Items gone from the library are dropped after each sync.
    private(set) var coverShuffles: [String: Int]
    @ObservationIgnored private let coverShufflesKey: String
    /// Runs after each successful sync (downloaded-playlist refresh).
    @ObservationIgnored var afterSync: (() async -> Void)?

    init(session: ServerSession, token: String, auth: AuthService, database: LibraryDatabase) {
        self.database = database
        self.api = LibraryClient(session: session, token: token, auth: auth)
        let sync = LibrarySync(session: session, token: token, auth: auth, database: database)
        self.sync = sync
        self.editor = LibraryEditor(session: session, token: token, auth: auth, database: database, sync: sync)
        self.hasSyncedOnce = (try? database.syncState()?.lastCompleted) != nil
        self.coverShufflesKey = Self.coverShufflesKey(serverID: session.serverID, userID: session.userID)
        self.coverShuffles = UserDefaults.standard.dictionary(forKey: coverShufflesKey) as? [String: Int] ?? [:]
    }

    private static func coverShufflesKey(serverID: String, userID: String) -> String { "coverShuffles.\(serverID).\(userID)" }

    /// Sign-out: the shuffle counts are this account's, kept on the device.
    static func clearStored(serverID: String, userID: String) {
        UserDefaults.standard.removeObject(forKey: coverShufflesKey(serverID: serverID, userID: userID))
    }

    func syncIfNeeded() async {
        guard (try? await sync.needsSync()) ?? true else { return }
        await syncNow()
    }

    func syncNow() async {
        guard !shuttingDown else { return }
        // A manual refresh joins an automatic sync already in flight before reloading shelves.
        if let syncTask {
            await syncTask.value
            return
        }
        let task = Task { await performSync() }
        syncTask = task
        await task.value
        syncTask = nil
    }

    func shutdown() async -> Bool {
        shuttingDown = true
        syncTask?.cancel()
        await syncTask?.value
        syncTask = nil
        do {
            try database.pool.close()
            return true
        } catch {
            return false
        }
    }

    private func performSync() async {
        isSyncing = true
        syncError = nil
        defer {
            isSyncing = false
            progress = nil
        }
        // Send plays from offline listening first, so the sync pulls counts that include them.
        await reportPendingPlays()
        do {
            try Task.checkCancellation()
            try await sync.run { [weak self] progress in
                Task { @MainActor in self?.progress = progress }
            }
            hasSyncedOnce = true
            pruneCoverShuffles()
            await afterSync?()
        } catch is CancellationError {
        } catch {
            syncError = "Library sync failed. Pull to retry."
        }
    }

    /// Sends plays recorded offline, oldest first; stops at the first failure (still offline)
    /// and tries again on the next sync. A play of a song the server no longer has is dropped,
    /// or it would hold up every play behind it for good.
    func reportPendingPlays() async {
        guard let plays = try? await database.pendingPlays() else { return }
        for play in plays {
            guard !Task.isCancelled else { return }
            guard let id = play.id, await api.markPlayed(trackID: play.trackID, at: play.playedAt) != .failed else { return }
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

    /// Feeds a query's results to `update` until the task is cancelled: the first value as-is,
    /// later ones with `animation`. A failure is logged and the screen keeps its last values.
    func observe<T: Sendable & Equatable>(_ observation: GRDBObservation<T>, animation: Animation? = nil, update: (T) -> Void) async {
        do {
            var loaded = false
            for try await value in observe(observation) {
                withAnimation(loaded ? animation : nil) { update(value) }
                loaded = true
            }
        } catch { Log.observationFailed(error) }
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
        saveCoverShuffles()
    }

    /// Keeps a shuffled cover's count when an item gets a new ID (a collection renamed by
    /// recreating it). Its cover still changes, since the ID is part of the seed.
    func moveCoverShuffle(from oldID: String, to newID: String) {
        guard let count = coverShuffles.removeValue(forKey: oldID) else { return }
        coverShuffles[newID] = count
        saveCoverShuffles()
    }

    /// Drops counts for playlists and collections that are no longer in the library.
    private func pruneCoverShuffles() {
        guard !coverShuffles.isEmpty, let ids = try? database.playlistAndCollectionIDs() else { return }
        let kept = coverShuffles.filter { ids.contains($0.key) }
        guard kept.count != coverShuffles.count else { return }
        coverShuffles = kept
        saveCoverShuffles()
    }

    private func saveCoverShuffles() {
        UserDefaults.standard.set(coverShuffles, forKey: coverShufflesKey)
    }

    /// Whether the account is a server admin. Only admins can change item images, so Upload and
    /// Remove Cover Image show only for them.
    private(set) var isAdmin = false
    /// The account's profile picture, shown in the profile drawer; nil without one.
    private(set) var avatarURL: URL?
    /// Admins rename a collection in place. Other accounts rename by recreating it, which needs
    /// collection management and deletion rights; without both, Rename is hidden for them.
    private(set) var canRenameCollections = false

    /// Reads the account's permissions and picture: at launch and whenever the app comes back to the
    /// foreground. A failed check (offline) keeps the last answer (and picture) instead of hiding the options.
    func loadPermissions() async {
        guard let account = try? await api.account() else { return }
        let policy = account.policy
        // Assigned even when nil, so a picture removed on the server disappears.
        avatarURL = account.avatarURL
        isAdmin = policy.isAdministrator
        canRenameCollections = policy.isAdministrator || (policy.canManageCollections && policy.canDeleteContent)
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
