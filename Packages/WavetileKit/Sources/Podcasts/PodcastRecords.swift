import CryptoKit
import Foundation
import GRDB

/// A host or guest named in a feed (Podcasting 2.0 `podcast:person`).
public struct PodcastPerson: Codable, Hashable, Sendable {
    public var name: String
    /// Lowercased role from the feed: "host", "guest", "producer"…
    public var role: String
    public var imageURL: URL?
    public var href: URL?

    public init(name: String, role: String = "host", imageURL: URL? = nil, href: URL? = nil) {
        self.name = name
        self.role = role
        self.imageURL = imageURL
        self.href = href
    }
}

/// A podcast the user follows, or one they're previewing from search (`followedAt == nil`).
public struct ShowRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "show"

    /// `PodcastID.show(feedURL:)`: stable across devices, so synced data lines up.
    public var id: String
    public var feedURL: URL
    public var title: String
    public var author: String
    public var summary: String
    public var artworkURL: URL?
    public var websiteURL: URL?
    /// `itunes:type` serial: episodes are meant to be heard in order, oldest first.
    public var isSerial: Bool
    public var followedAt: Date?
    public var lastRefreshed: Date?
    public var lastOpened: Date?
    /// Conditional GET validators from the last fetch.
    public var etag: String?
    public var lastModified: String?
    /// See `FeedValidators.bodyHash`.
    public var bodyHash: String?
    /// Per-show settings. nil means "use the app default".
    public var playbackRate: Double?
    public var autoDownload: Bool
    public var oldestFirst: Bool?
    public var hidePlayed: Bool
    /// The show's regular hosts; episodes can name their own.
    public var people: [PodcastPerson] = []

    public var isFollowed: Bool { followedAt != nil }
    /// Show episodes oldest first: the user's choice, else serial shows go in order.
    public var sortsOldestFirst: Bool { oldestFirst ?? isSerial }

    public init(
        id: String, feedURL: URL, title: String, author: String, summary: String,
        artworkURL: URL?, websiteURL: URL?, isSerial: Bool, followedAt: Date? = nil,
        lastRefreshed: Date? = nil, lastOpened: Date? = nil, etag: String? = nil, lastModified: String? = nil,
        playbackRate: Double? = nil, autoDownload: Bool = false, oldestFirst: Bool? = nil, hidePlayed: Bool = false
    ) {
        self.id = id
        self.feedURL = feedURL
        self.title = title
        self.author = author
        self.summary = summary
        self.artworkURL = artworkURL
        self.websiteURL = websiteURL
        self.isSerial = isSerial
        self.followedAt = followedAt
        self.lastRefreshed = lastRefreshed
        self.lastOpened = lastOpened
        self.etag = etag
        self.lastModified = lastModified
        self.playbackRate = playbackRate
        self.autoDownload = autoDownload
        self.oldestFirst = oldestFirst
        self.hidePlayed = hidePlayed
    }
}

public struct EpisodeRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "episode"

    /// `PodcastID.episode(feedURL:guid:)`.
    public var id: String
    public var showID: String
    public var guid: String
    public var title: String
    /// Plain-text summary for rows.
    public var summary: String
    /// Raw show notes HTML from the feed. Untrusted: render only through `ShowNotes`.
    public var notesHTML: String
    public var publishedAt: Date?
    public var duration: Double?
    public var audioURL: URL
    public var mimeType: String?
    public var byteLength: Int64?
    /// Episode art when the feed has its own; otherwise the show's art is used.
    public var artworkURL: URL?
    public var season: Int?
    public var number: Int?
    public var episodeType: String?
    /// Podcasting 2.0 JSON chapters.
    public var chaptersURL: URL?
    /// Podcasting 2.0 transcript, the most readable format the feed offers, and its MIME type.
    public var transcriptURL: URL?
    public var transcriptType: String?
    /// Hosts and guests named on this episode; empty means the show's hosts.
    public var people: [PodcastPerson] = []
    /// Resume point in seconds; 0 when unplayed or finished.
    public var position: Double
    public var playedAt: Date?
    public var lastPlayedAt: Date?
    public var savedAt: Date?
    /// When this device first saw the episode (drives "new" badges).
    public var firstSeenAt: Date
    /// Still in the feed as of the last refresh.
    public var generation: Int

    public var isPlayed: Bool { playedAt != nil }
    public var isInProgress: Bool { position > 0 && playedAt == nil }
    public var isSaved: Bool { savedAt != nil }

    /// Seconds left, when the length is known.
    public var remaining: Double? {
        guard let duration, duration > 0 else { return nil }
        return max(duration - position, 0)
    }

    public var progress: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(position / duration, 1)
    }

    public init(
        id: String, showID: String, guid: String, title: String, summary: String, notesHTML: String,
        publishedAt: Date?, duration: Double?, audioURL: URL, mimeType: String? = nil, byteLength: Int64? = nil,
        artworkURL: URL? = nil, season: Int? = nil, number: Int? = nil, episodeType: String? = nil,
        chaptersURL: URL? = nil, position: Double = 0, playedAt: Date? = nil, lastPlayedAt: Date? = nil,
        savedAt: Date? = nil, firstSeenAt: Date = Date(), generation: Int = 0
    ) {
        self.id = id
        self.showID = showID
        self.guid = guid
        self.title = title
        self.summary = summary
        self.notesHTML = notesHTML
        self.publishedAt = publishedAt
        self.duration = duration
        self.audioURL = audioURL
        self.mimeType = mimeType
        self.byteLength = byteLength
        self.artworkURL = artworkURL
        self.season = season
        self.number = number
        self.episodeType = episodeType
        self.chaptersURL = chaptersURL
        self.position = position
        self.playedAt = playedAt
        self.lastPlayedAt = lastPlayedAt
        self.savedAt = savedAt
        self.firstSeenAt = firstSeenAt
        self.generation = generation
    }
}

/// The podcast Up Next queue, persisted so it survives relaunches.
public struct UpNextRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "upNext"
    public var episodeID: String
    public var sortOrder: Double

    public init(episodeID: String, sortOrder: Double) {
        self.episodeID = episodeID
        self.sortOrder = sortOrder
    }
}

/// Download state for one episode, and its file once finished.
public struct EpisodeDownloadRecord: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "episodeDownload"

    public enum State: String, Codable, Sendable {
        case queued, downloading, done, failed
    }

    public var episodeID: String
    public var state: State
    /// File name inside the podcast downloads directory (never an absolute path; containers move).
    public var fileName: String?
    public var bytes: Int64
    public var progress: Double
    public var error: String?
    public var requestedAt: Date
    /// Downloaded by the auto-download setting rather than by hand.
    public var isAutomatic: Bool

    public var id: String { episodeID }
    public var isInProgress: Bool { state == .queued || state == .downloading }

    public init(episodeID: String, state: State, fileName: String? = nil, bytes: Int64 = 0, progress: Double = 0,
                error: String? = nil, requestedAt: Date = Date(), isAutomatic: Bool = false) {
        self.episodeID = episodeID
        self.state = state
        self.fileName = fileName
        self.bytes = bytes
        self.progress = progress
        self.error = error
        self.requestedAt = requestedAt
        self.isAutomatic = isAutomatic
    }
}

/// An episode with the show it belongs to (and its download, if any), for lists that mix shows.
public struct EpisodeItem: Hashable, Sendable, Identifiable, FetchableRecord, Decodable {
    public var episode: EpisodeRecord
    public var show: ShowRecord
    public var download: EpisodeDownloadRecord?

    public var id: String { episode.id }
    /// Episode art, falling back to the show's.
    public var artworkURL: URL? { episode.artworkURL ?? show.artworkURL }

    public init(episode: EpisodeRecord, show: ShowRecord, download: EpisodeDownloadRecord? = nil) {
        self.episode = episode
        self.show = show
        self.download = download
    }

    enum CodingKeys: String, CodingKey {
        case episode, show, download = "episodeDownload"
    }
}

/// A followed show and how many unplayed episodes arrived since the user last opened it.
public struct ShowSummary: Hashable, Sendable, Identifiable, FetchableRecord {
    public var show: ShowRecord
    public var newCount: Int
    public var latestAt: Date?

    public var id: String { show.id }
}

/// Stable IDs derived from feed URLs and GUIDs, identical on every device.
public enum PodcastID {
    public static func show(feedURL: URL) -> String {
        hash(normalized(feedURL))
    }

    public static func episode(feedURL: URL, guid: String) -> String {
        hash(normalized(feedURL) + "\n" + guid)
    }

    /// Scheme and host are case-insensitive, and http/https name the same feed.
    static func normalized(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        let host = components?.host?.lowercased()
        components?.host = host
        return components?.string ?? url.absoluteString
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
