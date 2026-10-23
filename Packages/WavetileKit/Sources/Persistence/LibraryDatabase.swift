import Foundation
import GRDB

/// One SQLite database per server+user. `DatabasePool` (WAL) lets UI reads run concurrently
/// with sync writes, so browsing never blocks on a sync.
public final class LibraryDatabase: Sendable {
    public let pool: DatabasePool

    /// Opens (creating if needed) the library database in Application Support.
    public static func open(serverID: String, userID: String) throws -> LibraryDatabase {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Libraries", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appending(path: "\(safe(serverID))-\(safe(userID)).sqlite")
        let database = try LibraryDatabase(path: url.path(percentEncoded: false))
        // Re-downloadable cache: keep it out of iCloud/device backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return database
    }

    /// In-memory-ish database in a temp file, for tests and previews.
    public static func temporary() throws -> LibraryDatabase {
        let url = FileManager.default.temporaryDirectory.appending(path: "library-\(UUID().uuidString).sqlite")
        return try LibraryDatabase(path: url.path(percentEncoded: false))
    }

    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        pool = try DatabasePool(path: path, configuration: config)
        try Self.migrator.migrate(pool)
    }

    /// Removes the database file for a session (sign out).
    public static func delete(serverID: String, userID: String) {
        guard let directory = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appending(path: "Libraries", directoryHint: .isDirectory)
        else { return }
        let base = "\(safe(serverID))-\(safe(userID)).sqlite"
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: directory.appending(path: base + suffix))
        }
    }

    private static func safe(_ id: String) -> String {
        id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        // Schema changes during development: wipe and resync instead of writing migrations.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "artist") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("sortName", .text).notNull().indexed()
                t.column("imageTag", .text)
                t.column("generation", .integer).notNull()
            }

            try db.create(table: "album") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("sortTitle", .text).notNull().indexed()
                t.column("artistName", .text).notNull()
                t.column("artistID", .text).indexed()
                t.column("year", .integer)
                t.column("imageTag", .text)
                t.column("dateAdded", .datetime).indexed()
                t.column("generation", .integer).notNull()
            }

            try db.create(table: "albumGenre") { t in
                t.column("albumID", .text).notNull().references("album", onDelete: .cascade)
                t.column("genre", .text).notNull().indexed()
                t.primaryKey(["albumID", "genre"])
            }

            try db.create(table: "track") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("sortTitle", .text).notNull().indexed()
                t.column("albumID", .text).indexed()
                t.column("albumTitle", .text).notNull()
                t.column("artistName", .text).notNull()
                t.column("albumArtistName", .text).notNull()
                t.column("trackNumber", .integer)
                t.column("discNumber", .integer)
                t.column("durationMs", .integer)
                t.column("playCount", .integer).notNull().defaults(to: 0)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("lastPlayed", .datetime)
                t.column("dateAdded", .datetime)
                t.column("container", .text)
                t.column("generation", .integer).notNull()
            }

            try db.create(table: "playlist") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("imageTag", .text)
                t.column("trackCount", .integer).notNull()
                t.column("durationMs", .integer).notNull()
                t.column("generation", .integer).notNull()
            }

            try db.create(table: "playlistEntry") { t in
                t.column("playlistID", .text).notNull().references("playlist", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("trackID", .text).notNull()
                t.column("entryID", .text)
                t.primaryKey(["playlistID", "position"])
            }

            try db.create(table: "syncState") { t in
                t.primaryKey("id", .integer)
                t.column("generation", .integer).notNull()
                t.column("lastCompleted", .datetime)
            }

            // Full-text search kept in sync with the content tables by triggers.
            try db.create(virtualTable: "artistFTS", using: FTS5()) { t in
                t.synchronize(withTable: "artist")
                t.tokenizer = .unicode61()
                t.column("name")
            }
            try db.create(virtualTable: "albumFTS", using: FTS5()) { t in
                t.synchronize(withTable: "album")
                t.tokenizer = .unicode61()
                t.column("title")
                t.column("artistName")
            }
            try db.create(virtualTable: "trackFTS", using: FTS5()) { t in
                t.synchronize(withTable: "track")
                t.tokenizer = .unicode61()
                t.column("title")
                t.column("artistName")
                t.column("albumTitle")
            }
        }
        registerDownloadMigrations(&migrator)

        migrator.registerMigration("v3-favorites-collections") { db in
            try db.alter(table: "album") { t in t.add(column: "isFavorite", .boolean).notNull().defaults(to: false) }
            try db.alter(table: "artist") { t in t.add(column: "isFavorite", .boolean).notNull().defaults(to: false) }
            try db.create(table: "collection") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("sortName", .text).notNull().indexed()
                t.column("imageTag", .text)
                t.column("albumCount", .integer).notNull()
                t.column("generation", .integer).notNull()
            }
            try db.create(table: "collectionAlbum") { t in
                t.column("collectionID", .text).notNull().references("collection", onDelete: .cascade)
                t.column("albumID", .text).notNull()
                t.column("position", .integer).notNull()
                t.primaryKey(["collectionID", "albumID"])
            }
        }
        return migrator
    }
}
