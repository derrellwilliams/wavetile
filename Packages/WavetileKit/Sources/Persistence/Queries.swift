import Foundation
import GRDB

/// Read queries used by the UI. Sort columns hold keys pre-normalized at sync time
/// (`SortKey.make`), so ordering uses plain indexed comparisons, which is fast on 50k+ rows.
/// Most return a `ValueObservation` so screens update live
/// while a sync writes in the background.
public extension LibraryDatabase {
    enum AlbumSort: String, CaseIterable, Sendable {
        case title, artist, year, recentlyAdded
    }

    func artists() -> ValueObservation<ValueReducers.Fetch<[ArtistRecord]>> {
        ValueObservation.tracking { db in
            try ArtistRecord.order(Column("sortName")).fetchAll(db)
        }
    }

    func albums(sort: AlbumSort = .title) -> ValueObservation<ValueReducers.Fetch<[AlbumRecord]>> {
        ValueObservation.tracking { db in
            let request = AlbumRecord.all()
            let title = Column("sortTitle")
            let ordered = switch sort {
            case .title: request.order(title)
            case .artist: request.order(Column("artistName").collating(.nocase), Column("year"), title)
            case .year: request.order(Column("year").desc, title)
            case .recentlyAdded: request.order(Column("dateAdded").desc)
            }
            return try ordered.fetchAll(db)
        }
    }

    func albums(artistID: String) -> ValueObservation<ValueReducers.Fetch<[AlbumRecord]>> {
        ValueObservation.tracking { db in
            try AlbumRecord.filter(Column("artistID") == artistID).order(Column("year").desc, Column("sortTitle")).fetchAll(db)
        }
    }

    func albums(genre: String) -> ValueObservation<ValueReducers.Fetch<[AlbumRecord]>> {
        ValueObservation.tracking { db in
            try AlbumRecord.fetchAll(db, sql: """
                SELECT album.* FROM album
                JOIN albumGenre ON albumGenre.albumID = album.id
                WHERE albumGenre.genre = ?
                ORDER BY album.sortTitle
                """, arguments: [genre])
        }
    }

    func album(id: String) throws -> AlbumRecord? {
        try pool.read { try AlbumRecord.fetchOne($0, key: id) }
    }

    func artist(id: String) throws -> ArtistRecord? {
        try pool.read { try ArtistRecord.fetchOne($0, key: id) }
    }

    func tracks(albumID: String) throws -> [TrackRecord] {
        try pool.read { db in
            try TrackRecord.filter(Column("albumID") == albumID)
                .order(Column("discNumber"), Column("trackNumber"), Column("sortTitle"))
                .fetchAll(db)
        }
    }

    func allTracks() -> ValueObservation<ValueReducers.Fetch<[TrackRecord]>> {
        ValueObservation.tracking { db in
            try TrackRecord.order(Column("sortTitle")).fetchAll(db)
        }
    }

    func genres() -> ValueObservation<ValueReducers.Fetch<[GenreSummary]>> {
        ValueObservation.tracking { db in
            try GenreSummary.fetchAll(db, sql: """
                SELECT genre, COUNT(*) AS albumCount FROM albumGenre
                GROUP BY genre ORDER BY genre COLLATE NOCASE
                """)
        }
    }

    func playlists() -> ValueObservation<ValueReducers.Fetch<[PlaylistRecord]>> {
        ValueObservation.tracking { db in
            try PlaylistRecord.order(Column("name").collating(.nocase)).fetchAll(db)
        }
    }

    func tracks(playlistID: String) throws -> [TrackRecord] {
        try pool.read { db in
            try TrackRecord.fetchAll(db, sql: """
                SELECT track.* FROM playlistEntry
                JOIN track ON track.id = playlistEntry.trackID
                WHERE playlistEntry.playlistID = ?
                ORDER BY playlistEntry.position
                """, arguments: [playlistID])
        }
    }

    func syncState() throws -> SyncStateRecord? {
        try pool.read { try SyncStateRecord.fetchOne($0, key: 1) }
    }

    func isEmpty() throws -> Bool {
        try pool.read { try TrackRecord.fetchCount($0) == 0 && AlbumRecord.fetchCount($0) == 0 }
    }

    struct SearchResults: Sendable, Equatable {
        public var artists: [ArtistRecord] = []
        public var albums: [AlbumRecord] = []
        public var tracks: [TrackRecord] = []
        public var isEmpty: Bool { artists.isEmpty && albums.isEmpty && tracks.isEmpty }

        public init(artists: [ArtistRecord] = [], albums: [AlbumRecord] = [], tracks: [TrackRecord] = []) {
            self.artists = artists
            self.albums = albums
            self.tracks = tracks
        }
    }

    /// Prefix-matching full-text search ("radi kid" finds "Kid A" by Radiohead), ranked by relevance.
    func search(_ text: String, limit: Int = 25) throws -> SearchResults {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: text) else { return SearchResults() }
        return try pool.read { db in
            SearchResults(
                artists: try ArtistRecord.fetchAll(db, sql: """
                    SELECT artist.* FROM artist JOIN artistFTS ON artistFTS.rowid = artist.rowid
                    WHERE artistFTS MATCH ? ORDER BY rank LIMIT ?
                    """, arguments: [pattern, limit]),
                albums: try AlbumRecord.fetchAll(db, sql: """
                    SELECT album.* FROM album JOIN albumFTS ON albumFTS.rowid = album.rowid
                    WHERE albumFTS MATCH ? ORDER BY rank LIMIT ?
                    """, arguments: [pattern, limit]),
                tracks: try TrackRecord.fetchAll(db, sql: """
                    SELECT track.* FROM track JOIN trackFTS ON trackFTS.rowid = track.rowid
                    WHERE trackFTS MATCH ? ORDER BY rank LIMIT ?
                    """, arguments: [pattern, limit])
            )
        }
    }
}

public enum SortKey {
    /// Case- and diacritic-folded, leading "The/A/An" dropped: "The Beatles" → "beatles".
    public static func make(_ text: String) -> String {
        var key = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["the ", "a ", "an "] where key.hasPrefix(article) && key.count > article.count {
            key.removeFirst(article.count)
            break
        }
        return key
    }

    /// Section index letter for A–Z lists; digits and symbols go under "#".
    public static func section(_ key: String) -> String {
        guard let first = key.first, first.isLetter, first.isASCII else { return "#" }
        return String(first).uppercased()
    }
}

// MARK: - Favorites & collections

public extension LibraryDatabase {
    func favoriteTracks() -> ValueObservation<ValueReducers.Fetch<[TrackRecord]>> {
        ValueObservation.tracking { db in
            try TrackRecord.filter(Column("isFavorite") == true).order(Column("sortTitle")).fetchAll(db)
        }
    }

    func favoriteAlbums() -> ValueObservation<ValueReducers.Fetch<[AlbumRecord]>> {
        ValueObservation.tracking { db in
            try AlbumRecord.filter(Column("isFavorite") == true).order(Column("sortTitle")).fetchAll(db)
        }
    }

    func favoriteArtists() -> ValueObservation<ValueReducers.Fetch<[ArtistRecord]>> {
        ValueObservation.tracking { db in
            try ArtistRecord.filter(Column("isFavorite") == true).order(Column("sortName")).fetchAll(db)
        }
    }

    /// Live favorite flag for one item (album, artist, or track), for heart buttons.
    func isFavorite(itemID: String) -> ValueObservation<ValueReducers.Fetch<Bool>> {
        ValueObservation.tracking { db in
            try Bool.fetchOne(db, sql: """
                SELECT isFavorite FROM album WHERE id = :id
                UNION ALL SELECT isFavorite FROM artist WHERE id = :id
                UNION ALL SELECT isFavorite FROM track WHERE id = :id
                LIMIT 1
                """, arguments: ["id": itemID]) ?? false
        }
    }

    func setFavorite(itemID: String, _ isFavorite: Bool) async throws {
        try await pool.write { db in
            for table in ["album", "artist", "track"] {
                try db.execute(sql: "UPDATE \(table) SET isFavorite = ? WHERE id = ?", arguments: [isFavorite, itemID])
            }
        }
    }

    func collections() -> ValueObservation<ValueReducers.Fetch<[CollectionRecord]>> {
        ValueObservation.tracking { db in
            try CollectionRecord.order(Column("sortName")).fetchAll(db)
        }
    }

    func albums(collectionID: String) -> ValueObservation<ValueReducers.Fetch<[AlbumRecord]>> {
        ValueObservation.tracking { db in
            try AlbumRecord.fetchAll(db, sql: """
                SELECT album.* FROM collectionAlbum
                JOIN album ON album.id = collectionAlbum.albumID
                WHERE collectionAlbum.collectionID = ?
                ORDER BY collectionAlbum.position
                """, arguments: [collectionID])
        }
    }

    /// First few album covers, for collection mosaics.
    func collectionCovers(collectionID: String, limit: Int = 4) throws -> [AlbumRecord] {
        try pool.read { db in
            try AlbumRecord.fetchAll(db, sql: """
                SELECT album.* FROM collectionAlbum JOIN album ON album.id = collectionAlbum.albumID
                WHERE collectionAlbum.collectionID = ? ORDER BY collectionAlbum.position LIMIT ?
                """, arguments: [collectionID, limit])
        }
    }

    func playlistEntries(playlistID: String) throws -> [PlaylistEntryRecord] {
        try pool.read { try PlaylistEntryRecord.filter(Column("playlistID") == playlistID).order(Column("position")).fetchAll($0) }
    }

    func playlist(id: String) throws -> PlaylistRecord? {
        try pool.read { try PlaylistRecord.fetchOne($0, key: id) }
    }
}

/// A playlist row: the entry (position, Jellyfin entry ID for edits) and its track.
public struct PlaylistItem: Sendable, Equatable, Identifiable {
    public let entry: PlaylistEntryRecord
    public let track: TrackRecord
    public var id: String { entry.entryID ?? "\(entry.position)-\(entry.trackID)" }
}

public extension LibraryDatabase {
    func playlistItems(playlistID: String) -> ValueObservation<ValueReducers.Fetch<[PlaylistItem]>> {
        ValueObservation.tracking { db in
            let entries = try PlaylistEntryRecord.filter(Column("playlistID") == playlistID).order(Column("position")).fetchAll(db)
            let tracks = try TrackRecord.fetchAll(db, keys: Set(entries.map(\.trackID)))
            let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
            return entries.compactMap { entry in byID[entry.trackID].map { PlaylistItem(entry: entry, track: $0) } }
        }
    }

    func playlistObservation(id: String) -> ValueObservation<ValueReducers.Fetch<PlaylistRecord?>> {
        ValueObservation.tracking { try PlaylistRecord.fetchOne($0, key: id) }
    }
}

// MARK: - Home shelves from local play data (instant first frame, works offline)

public extension LibraryDatabase {
    /// Albums ordered by their most recently played track.
    func recentlyPlayedAlbums(limit: Int = 24) throws -> [AlbumRecord] {
        try pool.read { db in
            try AlbumRecord.fetchAll(db, sql: """
                SELECT album.* FROM album
                JOIN (SELECT albumID, MAX(lastPlayed) AS played FROM track
                      WHERE lastPlayed IS NOT NULL GROUP BY albumID) t ON t.albumID = album.id
                ORDER BY t.played DESC LIMIT ?
                """, arguments: [limit])
        }
    }

    /// Albums ranked by the summed play counts of their tracks.
    func mostPlayedAlbums(limit: Int = 24) throws -> [AlbumRecord] {
        try pool.read { db in
            try AlbumRecord.fetchAll(db, sql: """
                SELECT album.* FROM album
                JOIN (SELECT albumID, SUM(playCount) AS plays FROM track
                      WHERE playCount > 0 GROUP BY albumID) t ON t.albumID = album.id
                ORDER BY t.plays DESC, album.sortTitle LIMIT ?
                """, arguments: [limit])
        }
    }

    func recentlyAddedAlbums(limit: Int = 24) throws -> [AlbumRecord] {
        try pool.read { try AlbumRecord.order(Column("dateAdded").desc).limit(limit).fetchAll($0) }
    }
}
