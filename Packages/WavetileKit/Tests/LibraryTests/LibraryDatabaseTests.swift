import Foundation
import GRDB
import Testing
@testable import Library
@testable import Persistence

struct LibraryDatabaseTests {
    func makeTrack(_ id: String, _ title: String, artist: String = "Radiohead", album: String = "a1", number: Int? = nil, generation: Int = 1) -> TrackRecord {
        TrackRecord(
            id: id, title: title, sortTitle: SortKey.make(title), albumID: album, albumTitle: "In Rainbows",
            artistName: artist, albumArtistName: artist, trackNumber: number, discNumber: 1, durationMs: 200_000,
            playCount: 0, isFavorite: false, lastPlayed: nil, dateAdded: nil, container: "flac", generation: generation
        )
    }

    @Test func sortKeyDropsArticlesAndFolds() {
        #expect(SortKey.make("The Beatles") == "beatles")
        #expect(SortKey.make("Björk") == "bjork")
        #expect(SortKey.make("A") == "a")
        #expect(SortKey.section("beatles") == "B")
        #expect(SortKey.section("2pac") == "#")
    }

    @Test func tracksForAlbumAreOrdered() throws {
        let db = try LibraryDatabase.temporary()
        try db.pool.write { db in
            try self.makeTrack("t2", "Bodysnatchers", number: 2).insert(db)
            try self.makeTrack("t1", "15 Step", number: 1).insert(db)
        }
        #expect(try db.tracks(albumID: "a1").map(\.id) == ["t1", "t2"])
    }

    @Test func searchMatchesPrefixesAcrossColumns() throws {
        let db = try LibraryDatabase.temporary()
        try db.pool.write { db in
            try self.makeTrack("t1", "Weird Fishes/Arpeggi").insert(db)
            try self.makeTrack("t2", "Nude").insert(db)
            try self.makeTrack("t3", "Hounds of Love", artist: "Kate Bush").insert(db)
        }
        #expect(try db.search("weird fi").tracks.map(\.id) == ["t1"])
        #expect(try Set(db.search("radio").tracks.map(\.id)) == ["t1", "t2"])
        #expect(try db.search("zzz").isEmpty)
    }

    @Test func searchReflectsUpdatesAndDeletes() throws {
        let db = try LibraryDatabase.temporary()
        try db.pool.write { db in try self.makeTrack("t1", "Nude").insert(db) }
        try db.pool.write { db in
            var track = try TrackRecord.fetchOne(db, key: "t1")!
            track.title = "Big Ideas"
            try track.update(db)
        }
        #expect(try db.search("nude").isEmpty)
        #expect(try db.search("big").tracks.count == 1)
        try db.pool.write { db in _ = try TrackRecord.deleteOne(db, key: "t1") }
        #expect(try db.search("big").isEmpty)
    }

    @Test func genresCountAlbums() async throws {
        let db = try LibraryDatabase.temporary()
        try await db.pool.write { db in
            for id in ["a1", "a2"] {
                try AlbumRecord(id: id, title: id, sortTitle: id, artistName: "X", artistID: nil, year: nil, imageTag: nil, dateAdded: nil, generation: 1).insert(db)
            }
            try AlbumGenreRecord(albumID: "a1", genre: "Rock").insert(db)
            try AlbumGenreRecord(albumID: "a2", genre: "Rock").insert(db)
            try AlbumGenreRecord(albumID: "a2", genre: "Jazz").insert(db)
        }
        var genres: [GenreSummary] = []
        for try await value in db.genres().values(in: db.pool) {
            genres = value
            break
        }
        #expect(genres.map(\.genre) == ["Jazz", "Rock"])
        #expect(genres.map(\.albumCount) == [1, 2])
    }

    @Test func genreTagsSplitAndDropLabels() {
        #expect(GenreTag.split("Electronic, Classical") == ["Electronic", "Classical"])
        #expect(GenreTag.split("Hardcore Punk;Rock") == ["Hardcore Punk", "Rock"])
        #expect(GenreTag.split("Hip-Hop/Rap") == ["Hip-Hop", "Rap"])
        #expect(GenreTag.split("R&B") == ["R&B"])
        #expect(GenreTag.split("lbl:ANTI-").isEmpty)
    }

    @Test func genresMergeCaseAndHyphenSpellings() async throws {
        let db = try LibraryDatabase.temporary()
        try await db.pool.write { db in
            for id in ["a1", "a2", "a3"] {
                try AlbumRecord(id: id, title: id, sortTitle: id, artistName: "X", artistID: nil, year: nil, imageTag: nil,
                                dateAdded: nil, isFavorite: false, generation: 1).insert(db)
            }
            try AlbumGenreRecord(albumID: "a1", genre: "folk").insert(db)
            try AlbumGenreRecord(albumID: "a2", genre: "folk").insert(db)
            try AlbumGenreRecord(albumID: "a3", genre: "Folk").insert(db)
            try AlbumGenreRecord(albumID: "a1", genre: "Hip-Hop").insert(db)
            try AlbumGenreRecord(albumID: "a2", genre: "hip hop").insert(db)
        }
        var genres: [GenreSummary] = []
        for try await value in db.genres().values(in: db.pool) {
            genres = value
            break
        }
        #expect(genres.map(\.genre) == ["Folk", "Hip-Hop"])
        #expect(genres.map(\.albumCount) == [3, 2])

        var albums: [AlbumRecord] = []
        for try await value in db.albums(genre: "hip hop").values(in: db.pool) {
            albums = value
            break
        }
        #expect(albums.map(\.id) == ["a1", "a2"])
    }
}

struct SyncWriteTests {
    let base = LibraryDatabaseTests()

    @Test func upsertChangedSkipsUnchangedRows() throws {
        let db = try LibraryDatabase.temporary()
        let added = Date(timeIntervalSince1970: 1_700_000_000.123_456_7)
        var track = base.makeTrack("t1", "Nude")
        track.dateAdded = added
        try db.pool.write { db in try TrackRecord.upsertChanged([track], in: db) }

        // A later sync with the same content (sub-millisecond date noise) writes nothing.
        var again = track
        again.generation = 2
        again.dateAdded = added.addingTimeInterval(0.000_04)
        let unchanged = try db.pool.write { db in try TrackRecord.upsertChanged([again], in: db) }
        #expect(unchanged.isEmpty)

        again.title = "Big Ideas"
        let changed = try db.pool.write { db in
            try TrackRecord.upsertChanged([again, base.makeTrack("t2", "Reckoner")], in: db)
        }
        #expect(changed == ["t1", "t2"])
        #expect(try db.search("big").tracks.map(\.id) == ["t1"])
    }

    @Test func pruneKeepsOnlySeenIDs() throws {
        let db = try LibraryDatabase.temporary()
        try db.pool.write { db in
            for id in ["t1", "t2", "t3"] { try base.makeTrack(id, id).insert(db) }
            try LibraryDatabase.prune("track", keeping: ["t1", "t3"], in: db)
        }
        #expect(try db.pool.read { try TrackRecord.fetchAll($0).map(\.id).sorted() } == ["t1", "t3"])
    }
}

struct PendingPlayTests {
    @Test func offlinePlaysCountLocallyAndQueueInOrder() async throws {
        let db = try LibraryDatabase.temporary()
        try await db.pool.write { try LibraryDatabaseTests().makeTrack("t1", "Nude").insert($0) }
        let first = Date(timeIntervalSince1970: 1_700_000_000), second = first.addingTimeInterval(600)
        try await db.queuePlay(trackID: "t1", at: second)
        try await db.queuePlay(trackID: "t1", at: first)

        let track = try await db.pool.read { try TrackRecord.fetchOne($0, key: "t1") }
        #expect(track?.playCount == 2)
        let plays = try await db.pendingPlays()
        #expect(plays.map(\.playedAt) == [first, second])

        try await db.removePendingPlay(id: try #require(plays.first?.id))
        #expect(try await db.pendingPlays().count == 1)
    }
}
