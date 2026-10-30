import CryptoKit
import Foundation

/// Downloads and parses feeds, and keeps the database's shows up to date.
public struct FeedFetcher: Sendable {
    /// Feeds over this size are refused (hostile or broken feeds; the biggest real ones are a few MB).
    public static let maxBytes: Int64 = 15 * 1024 * 1024

    public enum Result: Sendable {
        case notModified
        case feed(ParsedFeed, FeedValidators)
    }

    private let session: URLSession
    private let database: PodcastDatabase

    public init(database: PodcastDatabase, session: URLSession = PodcastNetwork.session) {
        self.database = database
        self.session = session
    }

    /// Fetches a feed, honoring ETag/Last-Modified so unchanged feeds cost almost nothing.
    @concurrent public func fetch(_ feedURL: URL, validators: FeedValidators? = nil) async throws -> Result {
        guard let url = PodcastNetwork.secure(feedURL) else { throw FeedError.insecure }
        var request = URLRequest(url: url)
        if let etag = validators?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified = validators?.lastModified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 304 { return .notModified }
            try PodcastNetwork.check(http)
        }
        let data = try await PodcastNetwork.read(bytes, response, maxBytes: Int(Self.maxBytes))
        // The same bytes as last time: skip parsing and writing, as for a 304.
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let previous = validators?.bodyHash, previous == hash { return .notModified }
        let feed = try FeedParser.parse(data)
        let http = response as? HTTPURLResponse
        let newValidators = FeedValidators(
            etag: http?.value(forHTTPHeaderField: "ETag"),
            lastModified: http?.value(forHTTPHeaderField: "Last-Modified"),
            bodyHash: hash
        )
        return .feed(feed, newValidators)
    }

    /// Fetches and stores a show. `follow` subscribes; otherwise it's stored as a preview.
    @discardableResult
    public func load(feedURL: URL, follow: Bool) async throws -> PodcastDatabase.UpsertResult {
        let canonical = PodcastNetwork.secure(feedURL) ?? feedURL
        guard case let .feed(feed, validators) = try await fetch(canonical) else { throw FeedError.notAFeed }
        return try await database.upsert(feed: feed, feedURL: canonical, validators: validators, follow: follow)
    }

    /// Refreshes one show; returns IDs of episodes that are new to this device.
    public func refresh(_ show: ShowRecord) async throws -> [String] {
        let validators = FeedValidators(etag: show.etag, lastModified: show.lastModified, bodyHash: show.bodyHash)
        switch try await fetch(show.feedURL, validators: validators) {
        case .notModified:
            try await database.touch(showID: show.id)
            return []
        case let .feed(feed, validators):
            return try await database.upsert(feed: feed, feedURL: show.feedURL, validators: validators, follow: false).newEpisodeIDs
        }
    }

    /// Refreshes every followed show, four at a time. Failures are skipped (a dead feed
    /// shouldn't block the others); returns new episode IDs.
    public func refreshAll() async -> [String] {
        guard let shows = try? database.followedShowsNow() else { return [] }
        return await withTaskGroup(of: [String].self) { group in
            var iterator = shows.makeIterator()
            for _ in 0 ..< 4 {
                guard let show = iterator.next() else { break }
                group.addTask { (try? await refresh(show)) ?? [] }
            }
            var newIDs: [String] = []
            for await ids in group {
                newIDs += ids
                if let show = iterator.next() {
                    group.addTask { (try? await refresh(show)) ?? [] }
                }
            }
            return newIDs
        }
    }
}
