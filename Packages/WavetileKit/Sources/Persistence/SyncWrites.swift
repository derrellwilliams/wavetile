import Foundation
import GRDB

/// A library row written by sync, keyed by its Jellyfin ID.
public protocol SyncedRecord: FetchableRecord, PersistableRecord, Identifiable, Sendable where ID == String {
    var generation: Int { get set }
}

extension ArtistRecord: SyncedRecord {}
extension AlbumRecord: SyncedRecord {}
extension TrackRecord: SyncedRecord {}
extension PlaylistRecord: SyncedRecord {}
extension CollectionRecord: SyncedRecord {}

public extension SyncedRecord {
    /// Writes only the rows that are new or differ from what's stored, and returns their IDs.
    ///
    /// An unchanged library then costs no writes: no FTS trigger churn, no WAL growth, and no
    /// observation re-runs. Compared by database encoding (`databaseEquals`), so dates that only
    /// differ below SQLite's millisecond precision count as equal.
    @discardableResult
    static func upsertChanged(_ records: [Self], in db: Database) throws -> Set<String> {
        let stored = try fetchAll(db, keys: records.map(\.id))
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var written = Set<String>()
        for var record in records {
            if let old = byID[record.id] {
                // The generation alone never counts as a change.
                record.generation = old.generation
                if record.databaseEquals(old) { continue }
            }
            try record.upsert(db)
            written.insert(record.id)
        }
        return written
    }
}

public extension LibraryDatabase {
    /// Deletes rows of `table` whose ID isn't in `kept`: the items a complete sync pass didn't see.
    /// Goes through a temp table because a 50k-ID `NOT IN (?, …)` exceeds SQLite's variable limit.
    static func prune(_ table: String, keeping kept: Set<String>, in db: Database) throws {
        try db.execute(sql: "CREATE TEMP TABLE IF NOT EXISTS keptID (id TEXT PRIMARY KEY)")
        try db.execute(sql: "DELETE FROM keptID")
        let insert = try db.makeStatement(sql: "INSERT OR IGNORE INTO keptID (id) VALUES (?)")
        for id in kept { try insert.execute(arguments: [id]) }
        try db.execute(sql: "DELETE FROM \(table) WHERE id NOT IN (SELECT id FROM keptID)")
        try db.execute(sql: "DELETE FROM keptID")
    }
}
