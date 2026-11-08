import Foundation
import GRDB
import Testing
@testable import Podcasts

/// The podcast database is the source of truth for listening state and can't be re-synced, so an
/// update must carry a user's data through every migration untouched.
struct PodcastMigrationTests {
    func tempPath() -> String {
        FileManager.default.temporaryDirectory.appending(path: "podcasts-migration-\(UUID().uuidString).sqlite").path(percentEncoded: false)
    }

    /// A database as the first release left it (schema v1), holding one followed show, played episodes, Up Next and a download.
    func makeV1Database(at path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: path, configuration: config)
        try PodcastDatabase.migrator.migrate(pool, upTo: "v1")
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO show (id, feedURL, title, author, summary, isSerial, followedAt, etag, lastModified, autoDownload)
                VALUES ('s1', 'https://example.com/feed.xml', 'Show', 'Host', '', 0, '2026-10-01 00:00:00.000', 'etag-1', 'Mon, 01 Oct 2026 00:00:00 GMT', 1)
                """)
            for (id, position, played) in [("e1", 1234.5, true), ("e2", 0.0, false)] {
                try db.execute(sql: """
                    INSERT INTO episode (id, showID, guid, title, summary, notesHTML, audioURL, position, playedAt, firstSeenAt)
                    VALUES (?, 's1', ?, ?, '', '', 'https://cdn.example.com/a.mp3', ?, ?, '2026-10-02 00:00:00.000')
                    """, arguments: [id, id, "Episode \(id)", position, played ? "2026-10-03 00:00:00.000" : nil])
            }
            try db.execute(sql: "INSERT INTO upNext (episodeID, sortOrder) VALUES ('e2', 1.0)")
            try db.execute(sql: """
                INSERT INTO episodeDownload (episodeID, state, fileName, bytes, requestedAt)
                VALUES ('e1', 'done', 'e1.mp3', 4096, '2026-10-04 00:00:00.000')
                """)
        }
    }

    @Test func upgradeFromV1KeepsListeningState() throws {
        let path = tempPath()
        try makeV1Database(at: path)

        let db = try PodcastDatabase(path: path)
        try db.pool.read { db in
            let show = try #require(try Row.fetchOne(db, sql: "SELECT * FROM show WHERE id = 's1'"))
            #expect(show["title"] as String == "Show")
            #expect(show["followedAt"] as Date? != nil, "still followed")
            #expect(show["autoDownload"] as Bool == true)
            #expect(show["people"] as String == "[]", "v3 column defaults for existing rows")
            #expect(show["etag"] as String? == nil, "v3 drops validators so the next refresh fills new fields in")
            #expect(show["lastModified"] as String? == nil)
            #expect(show["bodyHash"] as String? == nil)

            let played = try #require(try Row.fetchOne(db, sql: "SELECT * FROM episode WHERE id = 'e1'"))
            #expect(played["position"] as Double == 1234.5)
            #expect(played["playedAt"] as Date? != nil)
            #expect(played["people"] as String == "[]")
            #expect(played["transcriptURL"] as String? == nil)

            #expect(try String.fetchAll(db, sql: "SELECT episodeID FROM upNext") == ["e2"])
            #expect(try Int.fetchOne(db, sql: "SELECT bytes FROM episodeDownload WHERE episodeID = 'e1'") == 4096)
        }
    }

    @Test func upgradeFromV1AddsLaterTablesAndIndexes() throws {
        let path = tempPath()
        try makeV1Database(at: path)
        let db = try PodcastDatabase(path: path)

        try db.pool.read { db in
            for table in ["showGenre", "recommendation", "dismissedShow"] {
                #expect(try db.tableExists(table), "\(table) exists after upgrade")
            }
            let indexes = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'"))
            for index in ["episode_on_showID_publishedAt", "episode_lastPlayedAt", "episode_savedAt"] {
                #expect(indexes.contains(index), "\(index) exists after upgrade")
            }
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try String.fetchOne(db, sql: "PRAGMA integrity_check") == "ok")
        }
    }

    @Test func upgradedDatabaseKeepsCascadesAndAcceptsNewRows() throws {
        let path = tempPath()
        try makeV1Database(at: path)
        let db = try PodcastDatabase(path: path)

        try db.pool.write { db in
            try db.execute(sql: "INSERT INTO showGenre (showID, genreIDs, resolvedAt) VALUES ('s1', '1301', '2026-11-01 00:00:00.000')")
            try db.execute(sql: "DELETE FROM show WHERE id = 's1'")
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode") == 0, "episodes cascade with their show")
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM upNext") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episodeDownload") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM showGenre") == 0)
        }
    }

    @Test func everyMigrationIsAppliedOnceAndReopeningIsANoOp() throws {
        let path = tempPath()
        try makeV1Database(at: path)
        _ = try PodcastDatabase(path: path)
        let reopened = try PodcastDatabase(path: path)

        let applied = try reopened.pool.read { try PodcastDatabase.migrator.appliedIdentifiers($0) }
        #expect(applied == Set(PodcastDatabase.migrator.migrations))
        #expect(applied.count == PodcastDatabase.migrator.migrations.count, "no migration is registered twice")
    }
}
