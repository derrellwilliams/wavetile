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

    func playlist(_ id: String, name: String = "Mix") -> PlaylistRecord {
        PlaylistRecord(id: id, name: name, imageTag: nil, trackCount: 0, durationMs: 0, generation: 1)
    }

    @Test func syncedDownloadsFollowTheirSourceButNotAnEmptyLibrary() async throws {
        let db = try LibraryDatabase.temporary()
        let mix = DownloadCollectionRecord(id: "pl1", kind: .playlist, name: "Mix", subtitle: "Playlist", imageTag: nil)
        let deleted = DownloadCollectionRecord(id: "pl2", kind: .playlist, name: "Old", subtitle: "Playlist", imageTag: nil)
        let favorites = DownloadCollectionRecord(id: DownloadCollectionRecord.favoritesID, kind: .favorites, name: "Favorites", subtitle: "Favorites", imageTag: nil)
        let album = DownloadCollectionRecord(id: "al1", kind: .album, name: "al1", subtitle: "A", imageTag: nil)
        try await db.pool.write { db in
            try self.track("t1", album: "al1", number: 1, favorite: true).insert(db)
            try self.track("t2", album: "al1", number: 2).insert(db)
            try self.playlist("pl1").insert(db)
            try PlaylistEntryRecord(playlistID: "pl1", position: 0, trackID: "t2", entryID: "e0").insert(db)
        }
        #expect(try db.syncedDownloadSource(mix) == .tracks(["t2"]))
        #expect(try db.syncedDownloadSource(deleted) == .gone)
        #expect(try db.syncedDownloadSource(favorites) == .tracks(["t1"]))
        #expect(try db.syncedDownloadSource(album) == .keep)

        // The server reports an empty library (drive unmounted, then rescanned): the sync prunes
        // every song and playlist, and the downloads are left alone.
        try await db.pool.write { db in
            try TrackRecord.deleteAll(db)
            try PlaylistRecord.deleteAll(db)
        }
        for download in [mix, deleted, favorites, album] {
            #expect(try db.syncedDownloadSource(download) == .keep)
        }
    }

    @Test func playlistLookupTreatsWildcardsAsText() async throws {
        let db = try LibraryDatabase.temporary()
        try await db.pool.write { db in
            try self.playlist("pl1", name: "100% Hits").insert(db)
            try self.playlist("pl2", name: "Road Trip").insert(db)
            try self.playlist("pl3", name: "lo_fi").insert(db)
        }
        #expect(try db.playlists(matching: "%").map(\.id) == ["pl1"])
        #expect(try db.playlists(matching: "_").map(\.id) == ["pl3"])
        #expect(try db.playlists(matching: "road").map(\.id) == ["pl2"])
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
