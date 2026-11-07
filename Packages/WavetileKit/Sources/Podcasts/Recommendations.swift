import Foundation
import GRDB

/// A show suggested on the Podcasts tab's Recommended for You shelf.
public struct RecommendedShow: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "recommendation"

    /// Apple's collection ID.
    public var directoryID: Int
    public var sortOrder: Int
    public var title: String
    public var author: String
    public var artworkURL: URL?
    public var feedURL: URL
    public var genre: String?
    /// Why it's here: "Because you follow Radiolab".
    public var reason: String
    /// The genres this set was built from; a change rebuilds it.
    var signature: String
    var fetchedAt: Date

    public var id: Int { directoryID }
}

/// A show the user's taste is read from: one they follow, or one they've played lately.
struct TasteSource: Hashable, Sendable {
    var showID: String
    var title: String
    var feedURL: URL
    var isFollowed: Bool
    /// Episodes played or started in the last 90 days.
    var recentPlays: Int
    /// Apple genre IDs, most specific first; empty when the directory had none.
    var genreIDs: [String]
    /// No genres yet (or a find-nothing result old enough to try again).
    var needsLookup: Bool

    /// How much this show counts: following is 1, and each recent play adds half (up to 8).
    var weight: Double { (isFollowed ? 1 : 0) + 0.5 * Double(min(recentPlays, 8)) }

    var genre: String? { genreIDs.first { $0 != "26" } }
}

struct GenreChoice: Hashable, Sendable {
    var genre: String
    var score: Double
    /// The show that counts most in this genre.
    var basedOn: TasteSource

    var reason: String {
        basedOn.isFollowed ? "Because you follow \(basedOn.title)" : "Because you listen to \(basedOn.title)"
    }
}

enum RecommendationEngine {
    /// The genres the user's shows lean toward, strongest first. A genre far behind the leader
    /// (under a quarter of its score) is noise and dropped.
    static func topGenres(_ sources: [TasteSource], limit: Int = 3) -> [GenreChoice] {
        var scores: [String: Double] = [:]
        var leaders: [String: TasteSource] = [:]
        for source in sources where source.weight > 0 {
            guard let genre = source.genre else { continue }
            scores[genre, default: 0] += source.weight
            // Heaviest leads; a tie goes to the earlier title so the result is stable.
            if let leader = leaders[genre], (source.weight, leader.title) <= (leader.weight, source.title) { continue }
            leaders[genre] = source
        }
        let ranked = scores.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
        guard let top = ranked.first?.value else { return [] }
        return ranked.prefix(limit)
            .filter { $0.value >= top * 0.25 }
            .compactMap { genre, score in leaders[genre].map { GenreChoice(genre: genre, score: score, basedOn: $0) } }
    }

    /// One pick from each genre in turn, so the strongest genre leads without crowding out the rest.
    static func interleave(_ lists: [[RecommendedShow]], limit: Int) -> [RecommendedShow] {
        var result: [RecommendedShow] = []
        var seen = Set<Int>()
        var index = 0
        while result.count < limit, lists.contains(where: { index < $0.count }) {
            for list in lists where index < list.count && result.count < limit {
                if seen.insert(list[index].directoryID).inserted { result.append(list[index]) }
            }
            index += 1
        }
        return result
    }
}

/// Builds Recommended for You from the user's own listening: the genres of the shows they follow
/// and play, weighted by how much they play, then those genres' popular shows from Apple's
/// directory, minus anything followed or waved away. Apple's charts rank by popularity, so this
/// is "popular in what you listen to", not collaborative filtering.
///
/// Privacy: only show titles (a handful per run, never music or episode data) go to Apple, from
/// the device, as with "You Might Also Like"; genre charts are keyed by genre ID alone.
public struct PodcastRecommender: Sendable {
    /// Directory searches per run. Apple allows about 20 a minute; the next run does the rest.
    static let lookupsPerRun = 4
    static let maxAge: TimeInterval = 24 * 3600
    static let shelfSize = 16

    private let database: PodcastDatabase
    private let directory: DirectoryClient

    public init(database: PodcastDatabase, directory: DirectoryClient = DirectoryClient()) {
        self.database = database
        self.directory = directory
    }

    /// Rebuilds the cached picks when the taste genres changed or they're a day old.
    public func refresh(force: Bool = false) async throws {
        var sources = try database.tasteSources()
        let pending = sources.filter(\.needsLookup).sorted { ($1.weight, $0.title) < ($0.weight, $1.title) }
            .prefix(Self.lookupsPerRun)
        for source in pending {
            // A failed search (offline, rate limited) stops the lookups; a show Apple lacks is
            // recorded as having no genre so it isn't searched again for a month.
            let found: DirectoryShow?
            do { found = try await directory.findShow(title: source.title, feedURL: source.feedURL) } catch { break }
            let genres = found?.genreIDs ?? []
            try await database.saveGenres(showID: source.showID, genreIDs: genres)
            if let index = sources.firstIndex(where: { $0.showID == source.showID }) {
                sources[index].genreIDs = genres
                sources[index].needsLookup = false
            }
        }

        let choices = RecommendationEngine.topGenres(sources)
        let signature = choices.map(\.genre).joined(separator: ",")
        guard !choices.isEmpty else {
            try await database.replaceRecommendations([])
            return
        }
        if !force, let cached = try database.cachedRecommendationState(), cached.signature == signature,
           Date().timeIntervalSince(cached.fetchedAt) < Self.maxAge {
            return
        }

        let now = Date()
        var lists: [[RecommendedShow]] = []
        var failure: (any Error)?
        let held = Set(sources.map(\.showID))
        for choice in choices {
            do {
                let shows = try await directory.popularShows(genre: choice.genre)
                lists.append(shows.compactMap { show in
                    guard let feedURL = show.feedURL, !held.contains(PodcastID.show(feedURL: feedURL)) else { return nil }
                    return RecommendedShow(
                        directoryID: show.id, sortOrder: 0, title: show.title, author: show.author,
                        artworkURL: show.artworkURL, feedURL: feedURL, genre: show.genre,
                        reason: choice.reason, signature: signature, fetchedAt: now
                    )
                })
            } catch {
                failure = error
            }
        }
        // Every chart failed: keep the old picks rather than blank the shelf.
        if lists.isEmpty, let failure { throw failure }
        let picks = RecommendationEngine.interleave(lists, limit: Self.shelfSize)
            .enumerated().map { index, show in
                var show = show
                show.sortOrder = index
                return show
            }
        try await database.replaceRecommendations(picks)
    }
}

extension PodcastDatabase {
    /// Followed shows and ones played in the last 90 days, with any genres already looked up.
    func tasteSources(now: Date = Date()) throws -> [TasteSource] {
        let since = now.addingTimeInterval(-90 * 86400)
        let retry = now.addingTimeInterval(-30 * 86400)
        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM (
                  SELECT s.id, s.title, s.feedURL, s.followedAt IS NOT NULL AS isFollowed,
                         (SELECT COUNT(*) FROM episode e WHERE e.showID = s.id AND e.lastPlayedAt > ?) AS recentPlays,
                         g.genreIDs, g.resolvedAt
                  FROM show s LEFT JOIN showGenre g ON g.showID = s.id
                ) WHERE isFollowed = 1 OR recentPlays > 0
                """, arguments: [since])
            return rows.compactMap { row -> TasteSource? in
                guard let feedURL = URL(string: row["feedURL"] as String) else { return nil }
                let stored: String? = row["genreIDs"]
                let genres = (stored ?? "").split(separator: ",").map(String.init)
                let resolvedAt: Date? = row["resolvedAt"]
                let needsLookup = stored == nil || (genres.isEmpty && (resolvedAt ?? .distantPast) < retry)
                return TasteSource(
                    showID: row["id"], title: row["title"], feedURL: feedURL, isFollowed: row["isFollowed"],
                    recentPlays: row["recentPlays"], genreIDs: genres, needsLookup: needsLookup
                )
            }
        }
    }

    func saveGenres(showID: String, genreIDs: [String], now: Date = Date()) async throws {
        try await pool.write { db in
            // The show can be deleted (unfollowed and cleaned up) while the lookup was in flight.
            guard try ShowRecord.exists(db, key: showID) else { return }
            try db.execute(
                sql: "INSERT OR REPLACE INTO showGenre (showID, genreIDs, resolvedAt) VALUES (?, ?, ?)",
                arguments: [showID, genreIDs.joined(separator: ","), now]
            )
        }
    }

    func cachedRecommendationState() throws -> (signature: String, fetchedAt: Date)? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT signature, fetchedAt FROM recommendation LIMIT 1") else { return nil }
            return (signature: row["signature"] as String, fetchedAt: row["fetchedAt"] as Date)
        }
    }

    func replaceRecommendations(_ shows: [RecommendedShow]) async throws {
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM recommendation")
            for show in shows { try show.insert(db) }
        }
    }
}

public extension PodcastDatabase {
    /// The shelf: cached picks, minus shows now followed and ones the user waved away, so
    /// following one takes it off the shelf at once.
    func recommendedShows() -> ValueObservation<ValueReducers.Fetch<[RecommendedShow]>> {
        ValueObservation.tracking { db in
            let held = Set(try String.fetchAll(db, sql: "SELECT id FROM show WHERE followedAt IS NOT NULL"))
            let dismissed = Set(try String.fetchAll(db, sql: "SELECT showID FROM dismissedShow"))
            return try RecommendedShow.order(Column("sortOrder")).fetchAll(db).filter {
                let id = PodcastID.show(feedURL: $0.feedURL)
                return !held.contains(id) && !dismissed.contains(id)
            }
        }
    }

    /// "Not Interested": never suggest this show again.
    func dismissRecommendation(feedURL: URL, now: Date = Date()) async throws {
        try await pool.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO dismissedShow (showID, dismissedAt) VALUES (?, ?)",
                arguments: [PodcastID.show(feedURL: feedURL), now]
            )
        }
    }
}
