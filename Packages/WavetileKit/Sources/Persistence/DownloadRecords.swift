import Foundation
import GRDB

/// An album or playlist the user chose to download. Playlists stay in sync with the server.
public struct DownloadCollectionRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "downloadCollection"

    public enum Kind: String, Codable, Sendable {
        case album, playlist
    }

    public var id: String
    public var kind: Kind
    public var name: String
    public var subtitle: String
    public var imageTag: String?
    public var addedAt: Date

    public init(id: String, kind: Kind, name: String, subtitle: String, imageTag: String?, addedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.name = name
        self.subtitle = subtitle
        self.imageTag = imageTag
        self.addedAt = addedAt
    }
}

/// Which collections want a track. A file is deleted when its last membership goes away.
public struct DownloadMembershipRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "downloadMembership"
    public var collectionID: String
    public var trackID: String

    public init(collectionID: String, trackID: String) {
        self.collectionID = collectionID
        self.trackID = trackID
    }
}

/// Per-track download state and the local file once finished.
public struct DownloadedTrackRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "downloadedTrack"

    public enum State: String, Codable, Sendable {
        case queued, downloading, done, failed
    }

    public var trackID: String
    public var state: State
    /// File name inside the user's downloads directory (never an absolute path; containers move).
    public var fileName: String?
    public var bytes: Int64
    public var progress: Double
    public var error: String?
    public var updatedAt: Date

    public var id: String { trackID }

    public init(trackID: String, state: State, fileName: String? = nil, bytes: Int64 = 0, progress: Double = 0, error: String? = nil, updatedAt: Date = Date()) {
        self.trackID = trackID
        self.state = state
        self.fileName = fileName
        self.bytes = bytes
        self.progress = progress
        self.error = error
        self.updatedAt = updatedAt
    }
}

/// Aggregate status for a collection's download button.
public struct DownloadStatus: Sendable, Equatable {
    public var total: Int
    public var done: Int
    public var failed: Int
    /// 0...1 across all tracks, counting partial progress of in-flight ones.
    public var progress: Double

    public static let none = DownloadStatus(total: 0, done: 0, failed: 0, progress: 0)

    public var isDownloaded: Bool { total > 0 && done == total }
    public var isInProgress: Bool { total > 0 && done + failed < total }
    public var isRequested: Bool { total > 0 }
}

/// A downloaded collection with its stats, for the Downloaded tab.
public struct DownloadedCollection: Sendable, Equatable, Identifiable {
    public var collection: DownloadCollectionRecord
    public var status: DownloadStatus
    public var bytes: Int64
    public var id: String { collection.id }
}
