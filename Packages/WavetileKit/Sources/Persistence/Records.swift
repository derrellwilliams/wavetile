import Foundation
import GRDB

// Local mirror of the user's Jellyfin music library. Rows carry the `generation` of the sync
// that last saw them; a completed full sync deletes rows from older generations (removed items).

public struct ArtistRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "artist"
    public var id: String
    public var name: String
    public var sortName: String
    public var imageTag: String?
    public var generation: Int

    public init(id: String, name: String, sortName: String, imageTag: String?, generation: Int) {
        self.id = id
        self.name = name
        self.sortName = sortName
        self.imageTag = imageTag
        self.generation = generation
    }
}

public struct AlbumRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "album"
    public var id: String
    public var title: String
    public var sortTitle: String
    public var artistName: String
    public var artistID: String?
    public var year: Int?
    public var imageTag: String?
    public var dateAdded: Date?
    public var generation: Int

    public init(
        id: String, title: String, sortTitle: String, artistName: String, artistID: String?,
        year: Int?, imageTag: String?, dateAdded: Date?, generation: Int
    ) {
        self.id = id
        self.title = title
        self.sortTitle = sortTitle
        self.artistName = artistName
        self.artistID = artistID
        self.year = year
        self.imageTag = imageTag
        self.dateAdded = dateAdded
        self.generation = generation
    }
}

public struct AlbumGenreRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "albumGenre"
    public var albumID: String
    public var genre: String

    public init(albumID: String, genre: String) {
        self.albumID = albumID
        self.genre = genre
    }
}

public struct TrackRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "track"
    public var id: String
    public var title: String
    public var sortTitle: String
    public var albumID: String?
    public var albumTitle: String
    public var artistName: String
    public var albumArtistName: String
    public var trackNumber: Int?
    public var discNumber: Int?
    public var durationMs: Int?
    public var playCount: Int
    public var isFavorite: Bool
    public var lastPlayed: Date?
    public var dateAdded: Date?
    public var container: String?
    public var generation: Int

    public init(
        id: String, title: String, sortTitle: String, albumID: String?, albumTitle: String,
        artistName: String, albumArtistName: String, trackNumber: Int?, discNumber: Int?,
        durationMs: Int?, playCount: Int, isFavorite: Bool, lastPlayed: Date?, dateAdded: Date?,
        container: String?, generation: Int
    ) {
        self.id = id
        self.title = title
        self.sortTitle = sortTitle
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.albumArtistName = albumArtistName
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.durationMs = durationMs
        self.playCount = playCount
        self.isFavorite = isFavorite
        self.lastPlayed = lastPlayed
        self.dateAdded = dateAdded
        self.container = container
        self.generation = generation
    }
}

public struct PlaylistRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "playlist"
    public var id: String
    public var name: String
    public var imageTag: String?
    public var trackCount: Int
    public var durationMs: Int
    public var generation: Int

    public init(id: String, name: String, imageTag: String?, trackCount: Int, durationMs: Int, generation: Int) {
        self.id = id
        self.name = name
        self.imageTag = imageTag
        self.trackCount = trackCount
        self.durationMs = durationMs
        self.generation = generation
    }
}

public struct PlaylistEntryRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "playlistEntry"
    public var playlistID: String
    public var position: Int
    public var trackID: String
    /// Jellyfin's per-entry ID, needed to remove or move a specific entry (duplicates allowed).
    public var entryID: String?

    public init(playlistID: String, position: Int, trackID: String, entryID: String?) {
        self.playlistID = playlistID
        self.position = position
        self.trackID = trackID
        self.entryID = entryID
    }
}

public struct SyncStateRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "syncState"
    public var id: Int = 1
    public var generation: Int
    public var lastCompleted: Date?

    public init(generation: Int, lastCompleted: Date?) {
        self.generation = generation
        self.lastCompleted = lastCompleted
    }
}

/// A genre with how many albums carry it.
public struct GenreSummary: Codable, Hashable, Sendable, Identifiable, FetchableRecord {
    public var genre: String
    public var albumCount: Int
    public var id: String { genre }
}
