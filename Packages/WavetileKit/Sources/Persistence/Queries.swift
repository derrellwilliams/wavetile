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
            try ArtistRecord.inLibrary().order(Column("sortName")).fetchAll(db)
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

    /// The newest albums, for the Music tab's shelf (uses the `dateAdded` index; no full-table read).
    func recentlyAddedAlbums(limit: Int) -> ValueObservation<ValueReducers.Fetch<[AlbumRecord]>> {
        ValueObservation.tracking { db in
            try AlbumRecord.order(Column("dateAdded").desc).limit(limit).fetchAll(db)
        }
    }

    func albums(artistID: String) -> ValueObservation<ValueReducers.Fetch<[AlbumRecord]>> {
        ValueObservation.tracking { db in
            try AlbumRecord.filter(Column("artistID") == artistID).order(Column("year").desc, Column("sortTitle")).fetchAll(db)
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

    /// An artist's songs album by album, in the artist page's order (newest album first).
    func tracks(artistID: String) throws -> [TrackRecord] {
        try pool.read { db in
            try TrackRecord.fetchAll(db, sql: """
                SELECT track.* FROM track JOIN album ON album.id = track.albumID
                WHERE album.artistID = ?
                ORDER BY album.year DESC, album.sortTitle, track.discNumber, track.trackNumber, track.sortTitle
                """, arguments: [artistID])
        }
    }

    /// The synced artists among `ids` that have albums here, in the order given.
    func artists(ids: [String]) throws -> [ArtistRecord] {
        let byID = try pool.read { try ArtistRecord.inLibrary().filter(keys: ids).fetchAll($0) }
            .reduce(into: [String: ArtistRecord]()) { $0[$1.id] = $1 }
        return ids.compactMap { byID[$0] }
    }

    /// Every song A–Z with a row index by ID, built here on the reader's queue rather than on
    /// the main actor (50k entries).
    func allTracks() -> ValueObservation<ValueReducers.Fetch<TrackList>> {
        ValueObservation.tracking { db in
            TrackList(try TrackRecord.order(Column("sortTitle")).fetchAll(db))
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
        try pool.read { db in try Self.search(text, limit: limit, in: db) }
    }

    /// The same search, read off the caller's actor (search-as-you-type).
    func search(_ text: String, limit: Int = 25) async throws -> SearchResults {
        try await pool.read { db in try Self.search(text, limit: limit, in: db) }
    }

    private static func search(_ text: String, limit: Int, in db: Database) throws -> SearchResults {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: text) else { return SearchResults() }
        do {
            return SearchResults(
                artists: try ArtistRecord.fetchAll(db, sql: """
                    SELECT artist.* FROM artist JOIN artistFTS ON artistFTS.rowid = artist.rowid
                    WHERE artistFTS MATCH ? AND \(ArtistRecord.hasAlbumsSQL) ORDER BY rank LIMIT ?
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

public struct TrackList: Sendable, Equatable {
    public let tracks: [TrackRecord]
    public let indexByID: [String: Int]

    public init(_ tracks: [TrackRecord] = []) {
        self.tracks = tracks
        indexByID = Dictionary(tracks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.tracks == rhs.tracks }
}

public extension ArtistRecord {
    /// Jellyfin's album-artist list also has artists with nothing in this library (a second
    /// album artist, or one whose albums were removed). Lists only show artists with an album here.
    static let hasAlbumsSQL = "EXISTS (SELECT 1 FROM album WHERE album.artistID = artist.id)"

    static func inLibrary() -> QueryInterfaceRequest<ArtistRecord> {
        filter(sql: hasAlbumsSQL)
    }
}

public extension LibraryDatabase {
    /// The IDs among `ids` that are albums in the synced library.
    func albumIDs(in ids: [String]) throws -> Set<String> {
        try pool.read { try Set(String.fetchAll($0, AlbumRecord.filter(keys: ids).select(Column("id")))) }
    }

    /// The IDs among `ids` that are songs in the synced library.
    func trackIDs(in ids: [String]) throws -> Set<String> {
        try pool.read { try Set(String.fetchAll($0, TrackRecord.filter(keys: ids).select(Column("id")))) }
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
            try ArtistRecord.inLibrary().filter(Column("isFavorite") == true).order(Column("sortName")).fetchAll(db)
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

// MARK: - One-shot lists for CarPlay, which shows a snapshot rather than observing

public extension LibraryDatabase {
    func albumList(limit: Int) throws -> [AlbumRecord] {
        try pool.read { try AlbumRecord.order(Column("sortTitle")).limit(limit).fetchAll($0) }
    }

    func albumList(artistID: String) throws -> [AlbumRecord] {
        try pool.read { try AlbumRecord.filter(Column("artistID") == artistID).order(Column("year").desc, Column("sortTitle")).fetchAll($0) }
    }

    func artistList(limit: Int) throws -> [ArtistRecord] {
        try pool.read { try ArtistRecord.inLibrary().order(Column("sortName")).limit(limit).fetchAll($0) }
    }

    func playlistList() throws -> [PlaylistRecord] {
        try pool.read { try PlaylistRecord.order(Column("name")).fetchAll($0) }
    }

    /// Playlists whose name contains `text` (playlists aren't in the search index).
    func playlists(matching text: String, limit: Int = 10) throws -> [PlaylistRecord] {
        try pool.read { try PlaylistRecord.filter(Column("name").like("%\(text)%")).order(Column("name")).limit(limit).fetchAll($0) }
    }

    func favoriteArtistList(limit: Int) throws -> [ArtistRecord] {
        try pool.read { try ArtistRecord.inLibrary().filter(Column("isFavorite") == true).order(Column("sortName")).limit(limit).fetchAll($0) }
    }
}

// MARK: - Plays to report later (offline listening)

public struct PendingPlay: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pendingPlay"
    public var id: Int64?
    public var trackID: String
    public var playedAt: Date
}

public extension LibraryDatabase {
    /// Keeps a play for later and counts it locally now, so Home's Recently Played and Most
    /// Played reflect offline listening right away.
    func queuePlay(trackID: String, at date: Date) async throws {
        try await pool.write { db in
            try PendingPlay(id: nil, trackID: trackID, playedAt: date).insert(db)
            try db.execute(sql: "UPDATE track SET playCount = playCount + 1, lastPlayed = ? WHERE id = ?", arguments: [date, trackID])
        }
    }

    func pendingPlays() async throws -> [PendingPlay] {
        try await pool.read { try PendingPlay.order(Column("playedAt")).fetchAll($0) }
    }

    func removePendingPlay(id: Int64) async throws {
        _ = try await pool.write { try PendingPlay.deleteOne($0, key: id) }
    }
}
