import Foundation
import GRDB

public extension LibraryDatabase {
    static func registerDownloadMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2-downloads") { db in
            try db.create(table: "downloadCollection") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull()
                t.column("subtitle", .text).notNull()
                t.column("imageTag", .text)
                t.column("addedAt", .datetime).notNull()
            }
            try db.create(table: "downloadMembership") { t in
                t.column("collectionID", .text).notNull().references("downloadCollection", onDelete: .cascade)
                t.column("trackID", .text).notNull().indexed()
                t.primaryKey(["collectionID", "trackID"])
            }
            try db.create(table: "downloadedTrack") { t in
                t.primaryKey("trackID", .text)
                t.column("state", .text).notNull().indexed()
                t.column("fileName", .text)
                t.column("bytes", .integer).notNull().defaults(to: 0)
                t.column("progress", .double).notNull().defaults(to: 0)
                t.column("error", .text)
                t.column("updatedAt", .datetime).notNull()
            }
        }
    }

    // MARK: Writes

    /// Records a collection and its tracks; returns track IDs that need a new download.
    func requestDownload(_ collection: DownloadCollectionRecord, trackIDs: [String]) async throws -> [String] {
        try await pool.write { db in
            try collection.upsert(db)
            var toFetch: [String] = []
            for trackID in trackIDs {
                try DownloadMembershipRecord(collectionID: collection.id, trackID: trackID).upsert(db)
                let existing = try DownloadedTrackRecord.fetchOne(db, key: trackID)
                if existing == nil || existing?.state == .failed {
                    try DownloadedTrackRecord(trackID: trackID, state: .queued).upsert(db)
                    toFetch.append(trackID)
                }
            }
            return toFetch
        }
    }

    /// Replaces a synced download's membership (playlist, collection, Favorites) with its current tracks.
    /// Returns (newTrackIDs to download, orphaned file names to delete).
    func syncDownloadedPlaylist(id: String, trackIDs: [String]) async throws -> (added: [String], orphanedFiles: [String]) {
        try await pool.write { db in
            let current = Set(try String.fetchAll(db, sql: "SELECT trackID FROM downloadMembership WHERE collectionID = ?", arguments: [id]))
            let wanted = Set(trackIDs)
            for removed in current.subtracting(wanted) {
                _ = try DownloadMembershipRecord.deleteOne(db, key: ["collectionID": id, "trackID": removed])
            }
            var added: [String] = []
            for trackID in wanted.subtracting(current) {
                try DownloadMembershipRecord(collectionID: id, trackID: trackID).insert(db)
                if try DownloadedTrackRecord.fetchOne(db, key: trackID) == nil {
                    try DownloadedTrackRecord(trackID: trackID, state: .queued).insert(db)
                    added.append(trackID)
                }
            }
            return (added, try Self.deleteOrphans(db))
        }
    }

    /// Removes a collection; returns file names no longer used by any collection.
    func removeDownload(collectionID: String) async throws -> [String] {
        try await pool.write { db in
            _ = try DownloadCollectionRecord.deleteOne(db, key: collectionID)
            return try Self.deleteOrphans(db)
        }
    }

    /// Removes everything; returns all file names.
    func removeAllDownloads() async throws -> [String] {
        try await pool.write { db in
            let files = try String.fetchAll(db, sql: "SELECT fileName FROM downloadedTrack WHERE fileName IS NOT NULL")
            try DownloadCollectionRecord.deleteAll(db)
            try DownloadedTrackRecord.deleteAll(db)
            return files
        }
    }

    /// Returns false when the track is no longer wanted (its collection was removed meanwhile).
    @discardableResult
    func updateDownload(trackID: String, _ change: @escaping @Sendable (inout DownloadedTrackRecord) -> Void) async throws -> Bool {
        try await pool.write { db in
            guard var record = try DownloadedTrackRecord.fetchOne(db, key: trackID) else { return false }
            // Only the changed columns: a progress tick then doesn't wake observers of `state`
            // (offline availability, Home's Downloaded row).
            try record.updateChanges(db) {
                change(&$0)
                $0.updatedAt = Date()
            }
            return true
        }
    }

    private static func deleteOrphans(_ db: Database) throws -> [String] {
        let orphans = try DownloadedTrackRecord.fetchAll(db, sql: """
            SELECT * FROM downloadedTrack
            WHERE trackID NOT IN (SELECT trackID FROM downloadMembership)
            """)
        for orphan in orphans { try orphan.delete(db) }
        return orphans.compactMap(\.fileName)
    }

    // MARK: Reads

    func downloadedFileName(trackID: String) -> String? {
        try? pool.read { db in
            try String.fetchOne(db, sql: "SELECT fileName FROM downloadedTrack WHERE trackID = ? AND state = 'done'", arguments: [trackID])
        }
    }

    /// Pausing affects shared songs in every collection; finished files are preserved.
    func setDownloadPaused(collectionID: String, paused: Bool) async throws {
        try await pool.write { db in
            try db.execute(sql: """
                UPDATE downloadedTrack SET state = ?, progress = 0, bytes = 0, error = NULL
                WHERE state IN (\(paused ? "'queued', 'downloading', 'failed'" : "'paused', 'failed'"))
                AND trackID IN (SELECT trackID FROM downloadMembership WHERE collectionID = ?)
                """, arguments: [paused ? "paused" : "queued", collectionID])
        }
    }

    func downloadTracks(collectionID: String) -> ValueObservation<ValueReducers.Fetch<[DownloadedTrackRecord]>> {
        ValueObservation.tracking { db in
            try DownloadedTrackRecord.fetchAll(db, sql: """
                SELECT t.* FROM downloadedTrack t JOIN downloadMembership m ON m.trackID = t.trackID
                WHERE m.collectionID = ? ORDER BY t.trackID
                """, arguments: [collectionID])
        }
    }

    func pendingDownloads() throws -> [DownloadedTrackRecord] {
        try pool.read { try DownloadedTrackRecord.filter(["queued", "downloading"].contains(Column("state"))).fetchAll($0) }
    }

    /// Finished downloads with their file names, to check the files are still on disk.
    func finishedDownloads() throws -> [DownloadedTrackRecord] {
        try pool.read { try DownloadedTrackRecord.filter(Column("state") == "done").fetchAll($0) }
    }

    /// Puts finished downloads whose file went missing back in the queue.
    func requeueDownloads(trackIDs: [String]) async throws {
        try await pool.write { db in
            for trackID in trackIDs {
                try db.execute(sql: """
                    UPDATE downloadedTrack SET state = 'queued', fileName = NULL, bytes = 0, progress = 0, error = NULL, updatedAt = ?
                    WHERE trackID = ? AND state = 'done'
                    """, arguments: [Date(), trackID])
            }
        }
    }

    /// Puts failed downloads back in the queue (a retry on launch) and returns their track IDs.
    func requeueFailedDownloads() async throws -> [String] {
        try await pool.write { db in
            let ids = try String.fetchAll(db, sql: "SELECT trackID FROM downloadedTrack WHERE state = 'failed'")
            try db.execute(sql: "UPDATE downloadedTrack SET state = 'queued', progress = 0, error = NULL WHERE state = 'failed'")
            return ids
        }
    }

    /// Every download, albums included.
    func allDownloadCollections() throws -> [DownloadCollectionRecord] {
        try pool.read { try DownloadCollectionRecord.fetchAll($0) }
    }

    /// Downloads that follow their source (playlists, collections, Favorites), to bring up to date
    /// after a library sync.
    func syncedDownloads() throws -> [DownloadCollectionRecord] {
        try pool.read { try DownloadCollectionRecord.filter(["playlist", "collection", "favorites"].contains(Column("kind"))).fetchAll($0) }
    }

    /// What a synced download should hold now, read from the library mirror.
    enum SyncedDownloadSource: Sendable, Equatable {
        /// Leave the download as it is.
        case keep
        /// Its playlist or collection no longer exists.
        case gone
        case tracks([String])
    }

    /// Where a download that follows its source stands after a sync. A mirror with no songs at
    /// all answers `keep`: a server that reports an empty library (its music drive unmounted,
    /// then rescanned) would otherwise take every downloaded playlist, collection and favorite
    /// with it, and those files are the only copy the listener can still play. They're kept
    /// until the library is back or the listener removes them.
    func syncedDownloadSource(_ download: DownloadCollectionRecord) throws -> SyncedDownloadSource {
        guard download.kind != .album, try pool.read({ try !TrackRecord.limit(1).isEmpty($0) }) else { return .keep }
        switch download.kind {
        case .album: return .keep
        case .playlist: return try playlist(id: download.id) == nil ? .gone : .tracks(tracks(playlistID: download.id).map(\.id))
        case .collection: return try collection(id: download.id) == nil ? .gone : .tracks(trackIDs(collectionID: download.id))
        case .favorites: return .tracks(try favoritesDownloadTrackIDs())
        }
    }

    /// Every song on a collection's albums, album by album in the collection's order.
    func trackIDs(collectionID: String) throws -> [String] {
        try pool.read { db in
            try String.fetchAll(db, sql: """
                SELECT track.id FROM collectionAlbum JOIN track ON track.albumID = collectionAlbum.albumID
                WHERE collectionAlbum.collectionID = ?
                ORDER BY collectionAlbum.position, track.discNumber, track.trackNumber, track.sortTitle
                """, arguments: [collectionID])
        }
    }

    /// What the Favorites download holds: favorite songs, and every song on a favorite album.
    /// Favorite artists aren't included; a whole discography is too much to pull down at once.
    func favoritesDownloadTrackIDs() throws -> [String] {
        try pool.read(Self.favoritesTrackIDs)
    }

    /// The Favorites download's songs while it exists (nil otherwise), so hearting or unhearting
    /// something updates it right away rather than at the next library sync.
    func favoritesDownloadTracks() -> ValueObservation<ValueReducers.Fetch<[String]?>> {
        ValueObservation.tracking { db in
            guard try DownloadCollectionRecord.exists(db, key: DownloadCollectionRecord.favoritesID) else { return nil }
            return try Self.favoritesTrackIDs(db)
        }
    }

    private static func favoritesTrackIDs(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT id FROM track WHERE isFavorite = 1
            UNION
            SELECT track.id FROM track JOIN album ON album.id = track.albumID WHERE album.isFavorite = 1
            """)
    }

    /// Downloads with at least one finished song, newest first: Home's Downloaded row. Reads only
    /// finished state, so it doesn't re-run on every progress tick like `downloadedCollections()`.
    func playableDownloads() -> ValueObservation<ValueReducers.Fetch<[DownloadCollectionRecord]>> {
        ValueObservation.tracking { db in
            try DownloadCollectionRecord.fetchAll(db, sql: """
                SELECT * FROM downloadCollection WHERE EXISTS (
                    SELECT 1 FROM downloadMembership m JOIN downloadedTrack d ON d.trackID = m.trackID
                    WHERE m.collectionID = downloadCollection.id AND d.state = 'done'
                ) ORDER BY addedAt DESC
                """)
        }
    }

    func downloadStatus(collectionID: String) -> ValueObservation<ValueReducers.Fetch<DownloadStatus>> {
        ValueObservation.tracking { db in
            try Self.status(db, collectionID: collectionID)
        }
    }

    /// Track IDs that are fully downloaded (row badges, offline availability).
    func downloadedTrackIDs() -> ValueObservation<ValueReducers.Fetch<Set<String>>> {
        ValueObservation.tracking(Self.downloadedTrackIDs)
    }

    /// The same set, read once (before an observation has delivered it, or with no UI at all).
    func downloadedTrackIDsNow() throws -> Set<String> {
        try pool.read(Self.downloadedTrackIDs)
    }

    /// Albums, playlists and collections with at least one downloaded song: what still plays
    /// offline, so screens can dim the rest.
    func offlineAvailability() -> ValueObservation<ValueReducers.Fetch<OfflineAvailability>> {
        ValueObservation.tracking { db in
            let done = "SELECT trackID FROM downloadedTrack WHERE state = 'done'"
            let albums = "SELECT DISTINCT albumID FROM track WHERE albumID IS NOT NULL AND id IN (\(done))"
            return OfflineAvailability(
                albumIDs: Set(try String.fetchAll(db, sql: albums)),
                playlistIDs: Set(try String.fetchAll(db, sql: "SELECT DISTINCT playlistID FROM playlistEntry WHERE trackID IN (\(done))")),
                collectionIDs: Set(try String.fetchAll(db, sql: "SELECT DISTINCT collectionID FROM collectionAlbum WHERE albumID IN (\(albums))"))
            )
        }
    }

    private static func downloadedTrackIDs(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT trackID FROM downloadedTrack WHERE state = 'done'"))
    }

    /// Every collection with its status and size, in one grouped query (download progress writes
    /// re-run this many times a second).
    func downloadedCollections() -> ValueObservation<ValueReducers.Fetch<[DownloadedCollection]>> {
        ValueObservation.tracking { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT m.collectionID AS id, COUNT(*) AS total,
                       SUM(t.state = 'done') AS done,
                       SUM(t.state = 'failed') AS failed,
                   SUM(t.state = 'paused') AS paused,
                       SUM(CASE WHEN t.state = 'done' THEN 1.0 ELSE t.progress END) AS progressSum,
                       COALESCE(SUM(t.bytes), 0) AS bytes
                FROM downloadMembership m JOIN downloadedTrack t ON t.trackID = m.trackID
                GROUP BY m.collectionID
                """)
            let stats: [String: Row] = Dictionary(
                rows.compactMap { row in (row["id"] as String?).map { ($0, row) } },
                uniquingKeysWith: { first, _ in first }
            )
            return try DownloadCollectionRecord.order(Column("addedAt").desc).fetchAll(db).map { collection in
                guard let row = stats[collection.id] else { return DownloadedCollection(collection: collection, status: .none, bytes: 0) }
                return DownloadedCollection(collection: collection, status: Self.status(row), bytes: row["bytes"] ?? 0)
            }
        }
    }

    func totalDownloadedBytes() -> ValueObservation<ValueReducers.Fetch<Int64>> {
        ValueObservation.tracking { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(bytes), 0) FROM downloadedTrack WHERE state = 'done'") ?? 0
        }
    }

    fileprivate static func status(_ db: Database, collectionID: String) throws -> DownloadStatus {
        let row = try Row.fetchOne(db, sql: """
            SELECT COUNT(*) AS total,
                   SUM(t.state = 'done') AS done,
                   SUM(t.state = 'failed') AS failed,
                   SUM(t.state = 'paused') AS paused,
                   SUM(CASE WHEN t.state = 'done' THEN 1.0 ELSE t.progress END) AS progressSum
            FROM downloadMembership m JOIN downloadedTrack t ON t.trackID = m.trackID
            WHERE m.collectionID = ?
            """, arguments: [collectionID])
        return row.map(status) ?? .none
    }

    fileprivate static func status(_ row: Row) -> DownloadStatus {
        let total: Int = row["total"] ?? 0
        guard total > 0 else { return .none }
        return DownloadStatus(
            total: total,
            done: row["done"] ?? 0,
            failed: row["failed"] ?? 0,
            paused: row["paused"] ?? 0,
            progress: (row["progressSum"] ?? 0.0) / Double(total)
        )
    }
}

public extension LibraryDatabase {
    /// One-shot status (inside an existing read).
    func downloadStatusNow(collectionID: String) throws -> DownloadStatus {
        try pool.read { try Self.status($0, collectionID: collectionID) }
    }
}
