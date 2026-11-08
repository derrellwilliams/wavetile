import Foundation
import GRDB
import Testing
@testable import Persistence

/// An update must open a database written by an older release. The library is a re-downloadable
/// cache, but downloads, pending plays and the schema itself still have to survive an upgrade.
struct LibraryMigrationTests {
    func tempPath() -> String {
        FileManager.default.temporaryDirectory.appending(path: "library-migration-\(UUID().uuidString).sqlite").path(percentEncoded: false)
    }

    /// A database as the first release left it (schema v1) with one artist, album and track.
    func makeV1Database(at path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: path, configuration: config)
        try LibraryDatabase.migrator.migrate(pool, upTo: "v1")
        try pool.write { db in
            try db.execute(sql: "INSERT INTO artist (id, name, sortName, generation) VALUES ('ar1', 'Radiohead', 'radiohead', 1)")
            try db.execute(sql: """
                INSERT INTO album (id, title, sortTitle, artistName, artistID, year, generation)
                VALUES ('a1', 'In Rainbows', 'in rainbows', 'Radiohead', 'ar1', 2007, 1)
                """)
            try db.execute(sql: """
                INSERT INTO track (id, title, sortTitle, albumID, albumTitle, artistName, albumArtistName, playCount, generation)
                VALUES ('t1', 'Nude', 'nude', 'a1', 'In Rainbows', 'Radiohead', 'Radiohead', 7, 1)
                """)
        }
    }

    @Test func upgradeFromV1KeepsContentAndFillsNewColumns() throws {
        let path = tempPath()
        try makeV1Database(at: path)

        let db = try LibraryDatabase(path: path)
        try db.pool.read { db in
            let track = try #require(try Row.fetchOne(db, sql: "SELECT * FROM track WHERE id = 't1'"))
            #expect(track["title"] as String == "Nude")
            #expect(track["playCount"] as Int == 7)
            #expect(track["normalizationGain"] as Double? == nil, "filled by the next sync")
            #expect(track["albumImageTag"] as String? == nil, "filled by the next sync")

            let album = try #require(try Row.fetchOne(db, sql: "SELECT * FROM album WHERE id = 'a1'"))
            #expect(album["isFavorite"] as Bool == false, "v3 default for existing rows")
            #expect(try Bool.fetchOne(db, sql: "SELECT isFavorite FROM artist WHERE id = 'ar1'") == false)

            for table in ["downloadCollection", "downloadMembership", "downloadedTrack", "collection", "collectionAlbum", "pendingPlay"] {
                #expect(try db.tableExists(table), "\(table) exists after upgrade")
            }
            let indexes = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'"))
            for index in ["track_lastPlayed", "track_playCount", "track_favorite", "album_favorite", "artist_favorite"] {
                #expect(indexes.contains(index), "\(index) exists after upgrade")
            }
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try String.fetchOne(db, sql: "PRAGMA integrity_check") == "ok")
        }
    }

    @Test func searchStillWorksAfterUpgrade() throws {
        let path = tempPath()
        try makeV1Database(at: path)
        let db = try LibraryDatabase(path: path)

        #expect(try db.search("nude").tracks.map(\.id) == ["t1"])
        try db.pool.write { db in
            try db.execute(sql: "UPDATE track SET title = 'Big Ideas' WHERE id = 't1'")
        }
        #expect(try db.search("nude").isEmpty, "FTS triggers survive the ALTER TABLE migrations")
        #expect(try db.search("big").tracks.count == 1)
    }

    @Test func everyMigrationIsAppliedOnceAndReopeningIsANoOp() throws {
        let path = tempPath()
        try makeV1Database(at: path)
        _ = try LibraryDatabase(path: path)
        let reopened = try LibraryDatabase(path: path)

        let applied = try reopened.pool.read { try LibraryDatabase.migrator.appliedIdentifiers($0) }
        #expect(applied == Set(LibraryDatabase.migrator.migrations))
        #expect(applied.count == LibraryDatabase.migrator.migrations.count, "no migration is registered twice")
        #expect(try reopened.search("nude").tracks.count == 1, "data survives a reopen")
    }
}
