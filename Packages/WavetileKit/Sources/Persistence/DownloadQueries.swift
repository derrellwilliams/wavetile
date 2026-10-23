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

    /// Replaces a playlist's membership with its current tracks (auto-sync).
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

    func updateDownload(trackID: String, _ change: @escaping @Sendable (inout DownloadedTrackRecord) -> Void) async throws {
        try await pool.write { db in
            guard var record = try DownloadedTrackRecord.fetchOne(db, key: trackID) else { return }
            change(&record)
            record.updatedAt = Date()
            try record.update(db)
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

    func pendingDownloads() throws -> [DownloadedTrackRecord] {
        try pool.read { try DownloadedTrackRecord.filter(["queued", "downloading"].contains(Column("state"))).fetchAll($0) }
    }

    func downloadedPlaylistIDs() throws -> [String] {
        try pool.read { try String.fetchAll($0, sql: "SELECT id FROM downloadCollection WHERE kind = 'playlist'") }
    }

    func downloadStatus(collectionID: String) -> ValueObservation<ValueReducers.Fetch<DownloadStatus>> {
        ValueObservation.tracking { db in
            try Self.status(db, collectionID: collectionID)
        }
    }

    /// Track IDs that are fully downloaded (row badges, offline availability).
    func downloadedTrackIDs() -> ValueObservation<ValueReducers.Fetch<Set<String>>> {
        ValueObservation.tracking { db in
            Set(try String.fetchAll(db, sql: "SELECT trackID FROM downloadedTrack WHERE state = 'done'"))
        }
    }

    func downloadedCollections() -> ValueObservation<ValueReducers.Fetch<[DownloadedCollection]>> {
        ValueObservation.tracking { db in
            try DownloadCollectionRecord.order(Column("addedAt").desc).fetchAll(db).map { collection in
                let bytes = try Int64.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(t.bytes), 0) FROM downloadMembership m
                    JOIN downloadedTrack t ON t.trackID = m.trackID WHERE m.collectionID = ?
                    """, arguments: [collection.id]) ?? 0
                return DownloadedCollection(collection: collection, status: try Self.status(db, collectionID: collection.id), bytes: bytes)
            }
        }
    }

    func totalDownloadedBytes() -> ValueObservation<ValueReducers.Fetch<Int64>> {
        ValueObservation.tracking { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(bytes), 0) FROM downloadedTrack WHERE state = 'done'") ?? 0
        }
    }

    private static func status(_ db: Database, collectionID: String) throws -> DownloadStatus {
        let row = try Row.fetchOne(db, sql: """
            SELECT COUNT(*) AS total,
                   SUM(t.state = 'done') AS done,
                   SUM(t.state = 'failed') AS failed,
                   SUM(CASE WHEN t.state = 'done' THEN 1.0 ELSE t.progress END) AS progressSum
            FROM downloadMembership m JOIN downloadedTrack t ON t.trackID = m.trackID
            WHERE m.collectionID = ?
            """, arguments: [collectionID])
        let total: Int = row?["total"] ?? 0
        guard total > 0 else { return .none }
        return DownloadStatus(
            total: total,
            done: row?["done"] ?? 0,
            failed: row?["failed"] ?? 0,
            progress: (row?["progressSum"] ?? 0.0) / Double(total)
        )
    }
}
