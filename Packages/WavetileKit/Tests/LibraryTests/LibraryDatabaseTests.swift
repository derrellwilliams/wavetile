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
