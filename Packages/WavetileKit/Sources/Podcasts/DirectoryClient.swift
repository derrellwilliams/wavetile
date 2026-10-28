import Foundation

/// A show from Apple's podcast directory (search results and charts).
public struct DirectoryShow: Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var author: String
    public var artworkURL: URL?
    public var feedURL: URL?
    public var genre: String?
    /// Apple genre IDs, most specific first ("26" is the catch-all Podcasts genre).
    var genreIDs: [String] = []

    public init(id: Int, title: String, author: String, artworkURL: URL?, feedURL: URL?, genre: String?) {
        self.id = id
        self.title = title
        self.author = author
        self.artworkURL = artworkURL
        self.feedURL = feedURL
        self.genre = genre
    }
}

/// Apple's free, keyless podcast directory: the iTunes Search API for search and feed URLs, and
/// the Apple Marketing Tools RSS feed for top charts.
///
/// Privacy: only podcast search terms are sent (never music searches), straight from the device.
/// Apple limits the search API to roughly 20 requests a minute per IP, so callers debounce.
public struct DirectoryClient: Sendable {
    private let session: URLSession
    private let country: String

    public init(session: URLSession = PodcastNetwork.session, country: String? = nil) {
        self.session = session
        self.country = (country ?? Locale.current.region?.identifier ?? "us").lowercased()
    }

    public func search(_ term: String, limit: Int = 25) async throws -> [DirectoryShow] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            .init(name: "media", value: "podcast"),
            .init(name: "entity", value: "podcast"),
            .init(name: "limit", value: String(limit)),
            .init(name: "country", value: country),
            .init(name: "term", value: trimmed),
        ]
        return try await lookupResults(components.url!).filter { $0.feedURL != nil }
    }

    /// Today's top shows. Chart entries lack feed URLs, so they're resolved with one lookup.
    public func topShows(limit: Int = 25) async throws -> [DirectoryShow] {
        let url = URL(string: "https://rss.marketingtools.apple.com/api/v2/\(country)/podcasts/top/\(limit)/podcasts.json")!
        let (data, response) = try await session.data(from: url)
        try PodcastNetwork.check(response)
        let chart = try JSONDecoder().decode(Chart.self, from: data)
        let ids = chart.feed.results.compactMap { Int($0.id) }
        guard !ids.isEmpty else { return [] }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            .init(name: "id", value: ids.map(String.init).joined(separator: ",")),
            .init(name: "entity", value: "podcast"),
            .init(name: "country", value: country),
        ]
        let byID = try await lookupResults(components.url!).reduce(into: [Int: DirectoryShow]()) { $0[$1.id] = $1 }
        return ids.compactMap { byID[$0] }.filter { $0.feedURL != nil }
    }

    /// Popular shows in the same Apple genre: the show is found by searching its title and
    /// matching the feed, then that genre's top chart is read. Sends only the show's title.
    public func similarShows(title: String, feedURL: URL, limit: Int = 12) async throws -> [DirectoryShow] {
        let matches = try await search(title, limit: 10)
        let show = matches.first { Self.sameFeed($0.feedURL, feedURL) }
            ?? matches.first { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
        guard let genre = show?.genreIDs.first(where: { $0 != "26" }) else { return [] }

        let chart = URL(string: "https://itunes.apple.com/\(country)/rss/toppodcasts/limit=30/genre=\(genre)/json")!
        let (data, response) = try await session.data(from: chart)
        try PodcastNetwork.check(response)
        let ids = try JSONDecoder().decode(GenreChart.self, from: data).feed.entry
            .compactMap { Int($0.id.attributes.id) }
            .filter { $0 != show?.id }
        guard !ids.isEmpty else { return [] }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            .init(name: "id", value: ids.map(String.init).joined(separator: ",")),
            .init(name: "entity", value: "podcast"),
            .init(name: "country", value: country),
        ]
        let byID = try await lookupResults(components.url!).reduce(into: [Int: DirectoryShow]()) { $0[$1.id] = $1 }
        return ids.compactMap { byID[$0] }
            .filter { $0.feedURL != nil && !Self.sameFeed($0.feedURL, feedURL) }
            .prefix(limit)
            .map(\.self)
    }

    /// Feed URLs often differ only in scheme or a trailing slash.
    private static func sameFeed(_ a: URL?, _ b: URL) -> Bool {
        guard let a else { return false }
        func key(_ url: URL) -> String {
            var text = url.absoluteString.lowercased()
            if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
            return text.hasSuffix("/") ? String(text.dropLast()) : text
        }
        return key(a) == key(b)
    }

    private func lookupResults(_ url: URL) async throws -> [DirectoryShow] {
        let (data, response) = try await session.data(from: url)
        try PodcastNetwork.check(response)
        return try JSONDecoder().decode(SearchResponse.self, from: data).results.compactMap { result in
            guard let id = result.collectionId, let title = result.collectionName else { return nil }
            var show = DirectoryShow(
                id: id, title: title, author: result.artistName ?? "",
                artworkURL: FeedParser.webURL(result.artworkUrl600 ?? result.artworkUrl100),
                feedURL: FeedParser.webURL(result.feedUrl),
                genre: result.primaryGenreName
            )
            show.genreIDs = result.genreIds ?? []
            return show
        }
    }

    private struct SearchResponse: Decodable {
        var results: [Result]
        struct Result: Decodable {
            var collectionId: Int?
            var collectionName: String?
            var artistName: String?
            var feedUrl: String?
            var artworkUrl600: String?
            var artworkUrl100: String?
            var primaryGenreName: String?
            var genreIds: [String]?
        }
    }

    /// The older iTunes RSS chart, the one that can be filtered by genre.
    private struct GenreChart: Decodable {
        var feed: Feed
        struct Feed: Decodable { var entry: [Entry] }
        struct Entry: Decodable {
            var id: ID
            struct ID: Decodable {
                var attributes: Attributes
                struct Attributes: Decodable {
                    var id: String
                    enum CodingKeys: String, CodingKey { case id = "im:id" }
                }
            }
        }
    }

    private struct Chart: Decodable {
        var feed: Feed
        struct Feed: Decodable { var results: [Entry] }
        struct Entry: Decodable { var id: String }
    }
}

/// Network settings for everything podcast-related: feeds, directory, chapters.
///
/// Security: a separate ephemeral session with no cookies, no credential storage and no
/// Jellyfin headers, so nothing about the user's server or account reaches podcast hosts.
public enum PodcastNetwork {
    public static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = ["User-Agent": "Wavetile/1.0 (iOS; podcast player)"]
        return URLSession(configuration: config)
    }()

    static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw FeedError.http(http.statusCode)
        }
    }

    /// Feeds must be fetched over HTTPS (App Transport Security). `http://` links are upgraded.
    public static func secure(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme?.lowercased() {
        case "https": return url
        case "http", "feed", "pcast", "itpc", "podcast":
            components.scheme = "https"
            return components.url
        default: return nil
        }
    }
}
