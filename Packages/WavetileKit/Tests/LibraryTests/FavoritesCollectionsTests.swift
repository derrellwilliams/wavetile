import Foundation
import GRDB
import Testing
@testable import Persistence

struct FavoritesCollectionsTests {
    func album(_ id: String) -> AlbumRecord {
        AlbumRecord(id: id, title: id, sortTitle: id, artistName: "A", artistID: nil, year: nil, imageTag: nil, dateAdded: nil, generation: 1)
    }

    func track(_ id: String, album: String, number: Int, favorite: Bool = false) -> TrackRecord {
        TrackRecord(
            id: id, title: id, sortTitle: id, albumID: album, albumTitle: album, artistName: "A", albumArtistName: "A",
            trackNumber: number, discNumber: 1, durationMs: 1000, playCount: 0, isFavorite: favorite,
            lastPlayed: nil, dateAdded: nil, container: "flac", generation: 1
        )
    }

    func first<T: Sendable>(_ observation: ValueObservation<ValueReducers.Fetch<T>>, in db: LibraryDatabase) async throws -> T? {
        for try await value in observation.values(in: db.pool) { return value }
        return nil
    }

    @Test func favoriteFlagAppliesToWhicheverTableHasTheItem() async throws {
        let db = try LibraryDatabase.temporary()
        try await db.pool.write { db in try self.album("al1").insert(db) }
        #expect(try await first(db.isFavorite(itemID: "al1"), in: db) == false)
        try await db.setFavorite(itemID: "al1", true)
        #expect(try await first(db.isFavorite(itemID: "al1"), in: db) == true)
        #expect(try await first(db.favoriteAlbums(), in: db)?.map(\.id) == ["al1"])
    }

    @Test func collectionAlbumsKeepServerOrderAndCascadeOnDelete() async throws {
        let db = try LibraryDatabase.temporary()
        try await db.pool.write { db in
            for id in ["a", "b", "c"] { try self.album(id).insert(db) }
            try CollectionRecord(id: "col", name: "Road Trip", sortName: "road trip", imageTag: nil, albumCount: 2, generation: 1).insert(db)
            try CollectionAlbumRecord(collectionID: "col", albumID: "c", position: 0).insert(db)
            try CollectionAlbumRecord(collectionID: "col", albumID: "a", position: 1).insert(db)
        }
        #expect(try await first(db.albums(collectionID: "col"), in: db)?.map(\.id) == ["c", "a"])

        _ = try await db.pool.write { try CollectionRecord.deleteOne($0, key: "col") }
        #expect(try await db.pool.read { try CollectionAlbumRecord.fetchCount($0) } == 0)
    }

    @Test func collectionDownloadHasEverySongInCollectionOrder() async throws {
        let db = try LibraryDatabase.temporary()
        try await db.pool.write { db in
            for id in ["a", "c"] { try self.album(id).insert(db) }
            try self.track("a2", album: "a", number: 2).insert(db)
            try self.track("a1", album: "a", number: 1).insert(db)
            try self.track("c1", album: "c", number: 1).insert(db)
            try CollectionRecord(id: "col", name: "Road Trip", sortName: "road trip", imageTag: nil, albumCount: 2, generation: 1).insert(db)
            try CollectionAlbumRecord(collectionID: "col", albumID: "c", position: 0).insert(db)
            try CollectionAlbumRecord(collectionID: "col", albumID: "a", position: 1).insert(db)
        }
        #expect(try db.trackIDs(collectionID: "col") == ["c1", "a1", "a2"])
    }

    @Test func favoritesDownloadHasFavoriteSongsAndFavoriteAlbumsSongs() async throws {
        let db = try LibraryDatabase.temporary()
        try await db.pool.write { db in
            for id in ["a", "b"] { try self.album(id).insert(db) }
            try self.track("a1", album: "a", number: 1).insert(db)
            try self.track("a2", album: "a", number: 2).insert(db)
            try self.track("b1", album: "b", number: 1, favorite: true).insert(db)
            try self.track("b2", album: "b", number: 2).insert(db)
        }
        try await db.setFavorite(itemID: "a", true)
        #expect(Set(try db.favoritesDownloadTrackIDs()) == ["a1", "a2", "b1"])
    }
}
