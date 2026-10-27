import Foundation
import GRDB

/// Library-wide counts for Home's welcome card.
public struct LibraryStats: Hashable, Sendable {
    public var albums: Int
    public var artists: Int
    public var tracks: Int
}

// MARK: - Home discovery shelves (no play history needed)

public extension LibraryDatabase {
    func libraryStats() throws -> LibraryStats {
        try pool.read { db in
            try LibraryStats(
                albums: AlbumRecord.fetchCount(db),
                artists: ArtistRecord.fetchCount(db),
                tracks: TrackRecord.fetchCount(db)
            )
        }
    }

    func randomAlbums(limit: Int = 16) throws -> [AlbumRecord] {
        try pool.read { try AlbumRecord.order(sql: "random()").limit(limit).fetchAll($0) }
    }

    /// Random albums tagged with any spelling of `genre`.
    func randomAlbums(genre: String, limit: Int = 16) throws -> [AlbumRecord] {
        let key = GenreTag.keySQL("albumGenre.genre")
        return try pool.read { db in
            try AlbumRecord.fetchAll(db, sql: """
                SELECT album.* FROM album
                WHERE album.id IN (SELECT albumID FROM albumGenre WHERE \(key) = \(GenreTag.keySQL("?")))
                ORDER BY random() LIMIT ?
                """, arguments: [genre, limit])
        }
    }

    /// The genres with the most albums, largest first, spellings merged as in `genres()`.
    func topGenres(limit: Int) throws -> [GenreSummary] {
        let key = GenreTag.keySQL("genre")
        return try pool.read { db in
            try GenreSummary.fetchAll(db, sql: """
                WITH spelling AS (
                    SELECT \(key) AS k, genre, COUNT(*) AS n FROM albumGenre GROUP BY genre
                ), ranked AS (
                    SELECT k, genre, ROW_NUMBER() OVER (
                        PARTITION BY k ORDER BY unicode(genre) BETWEEN 65 AND 90 DESC, n DESC, genre
                    ) AS r FROM spelling
                ), counts AS (
                    SELECT \(key) AS k, COUNT(DISTINCT albumID) AS albumCount FROM albumGenre GROUP BY k
                )
                SELECT ranked.genre AS genre, counts.albumCount AS albumCount
                FROM ranked JOIN counts USING (k)
                WHERE r = 1
                ORDER BY albumCount DESC LIMIT ?
                """, arguments: [limit])
        }
    }

    /// A random artist for the spotlight, preferring ones with artwork and at least three albums.
    func spotlightArtist() throws -> (artist: ArtistRecord, albums: [AlbumRecord])? {
        try pool.read { db in
            guard let artist = try ArtistRecord.fetchOne(db, sql: """
                SELECT artist.* FROM artist
                JOIN (SELECT artistID, COUNT(*) AS n FROM album WHERE artistID IS NOT NULL GROUP BY artistID) a
                  ON a.artistID = artist.id
                ORDER BY (a.n >= 3 AND artist.imageTag IS NOT NULL) DESC, a.n >= 2 DESC, random()
                LIMIT 1
                """) else { return nil }
            let albums = try AlbumRecord.filter(Column("artistID") == artist.id)
                .order(Column("year").desc, Column("sortTitle"))
                .fetchAll(db)
            return (artist, albums)
        }
    }

    func playlistsByName(limit: Int = 16) throws -> [PlaylistRecord] {
        try pool.read { try PlaylistRecord.order(Column("name").collating(.nocase)).limit(limit).fetchAll($0) }
    }

    /// A random sample of tracks, for Shuffle All without loading the whole library.
    func randomTracks(limit: Int = 200) throws -> [TrackRecord] {
        try pool.read { try TrackRecord.order(sql: "random()").limit(limit).fetchAll($0) }
    }
}
