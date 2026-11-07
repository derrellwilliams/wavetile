import Foundation
import GRDB
import Testing
@testable import Podcasts

struct RecommendationTests {
    func source(_ title: String, genres: [String], followed: Bool = true, plays: Int = 0) -> TasteSource {
        TasteSource(
            showID: title, title: title, feedURL: URL(string: "https://example.com/\(title).xml")!,
            isFollowed: followed, recentPlays: plays, genreIDs: genres, needsLookup: false
        )
    }

    func pick(_ id: Int, feed: String? = nil) -> RecommendedShow {
        RecommendedShow(
            directoryID: id, sortOrder: id, title: "Show \(id)", author: "", artworkURL: nil,
            feedURL: URL(string: feed ?? "https://example.com/\(id).xml")!, genre: nil, reason: "Because", signature: "1", fetchedAt: Date()
        )
    }

    @Test func playsOutweighFollowsAndTheCatchAllGenreNeverCounts() {
        let sources = [
            source("A", genres: ["26", "1303"]),
            source("B", genres: ["1311"], plays: 6),
            source("C", genres: ["26"], plays: 8),
        ]
        let choices = RecommendationEngine.topGenres(sources)
        #expect(choices.map(\.genre) == ["1311", "1303"])
        #expect(choices.first?.basedOn.title == "B")
        #expect(choices.first?.reason == "Because you follow B")
    }

    @Test func playedButUnfollowedShowsSayListen() {
        let choices = RecommendationEngine.topGenres([source("A", genres: ["1303"], followed: false, plays: 2)])
        #expect(choices.first?.reason == "Because you listen to A")
        #expect(RecommendationEngine.topGenres([source("A", genres: ["1303"], followed: false, plays: 0)]).isEmpty)
    }

    @Test func aGenreFarBehindTheLeaderIsDropped() {
        let sources = [source("A", genres: ["1"], plays: 8), source("B", genres: ["2"])]
        #expect(RecommendationEngine.topGenres(sources).map(\.genre) == ["1"])
    }

    @Test func tiesBreakByTitleSoTheResultIsStable() {
        let sources = [source("Zed", genres: ["1"]), source("Abe", genres: ["1"]), source("Mid", genres: ["2"])]
        let choices = RecommendationEngine.topGenres(sources)
        #expect(choices.map(\.genre) == ["1", "2"])
        #expect(choices.first?.basedOn.title == "Abe")
    }

    @Test func interleaveAlternatesGenresAndDropsDuplicates() {
        let result = RecommendationEngine.interleave([[pick(1), pick(2), pick(3)], [pick(2), pick(4)]], limit: 10)
        #expect(result.map(\.directoryID) == [1, 2, 4, 3])
        #expect(RecommendationEngine.interleave([[pick(1), pick(2)], [pick(3), pick(4)]], limit: 3).map(\.directoryID) == [1, 3, 2])
    }

    @Test func tasteReadsFollowsAndRecentPlaysAndGenreLookups() async throws {
        let db = try PodcastDatabase.temporary()
        let followedFeed = URL(string: "https://example.com/followed.xml")!
        let previewedFeed = URL(string: "https://example.com/previewed.xml")!
        let idleFeed = URL(string: "https://example.com/idle.xml")!
        func feed(_ title: String) -> ParsedFeed {
            ParsedFeed(title: title, author: "", summary: "", artworkURL: nil, websiteURL: nil, isSerial: false, episodes: [
                ParsedEpisode(
                    guid: "e1", title: "E", summary: "", notesHTML: "", publishedAt: Date(), duration: 600,
                    audioURL: URL(string: "https://cdn.example.com/e.mp3")!, mimeType: nil, byteLength: nil,
                    artworkURL: nil, season: nil, number: nil, episodeType: nil, chaptersURL: nil
                ),
            ])
        }
        _ = try await db.upsert(feed: feed("Followed"), feedURL: followedFeed, validators: nil, follow: true)
        _ = try await db.upsert(feed: feed("Previewed"), feedURL: previewedFeed, validators: nil, follow: false)
        _ = try await db.upsert(feed: feed("Idle"), feedURL: idleFeed, validators: nil, follow: false)
        _ = try await db.savePosition(episodeID: PodcastID.episode(feedURL: previewedFeed, guid: "e1"), position: 60, duration: 600)

        var sources = try db.tasteSources().sorted { $0.title < $1.title }
        #expect(sources.map(\.title) == ["Followed", "Previewed"], "a show that's neither followed nor played isn't taste")
        #expect(sources.allSatisfy { $0.needsLookup })
        #expect(sources.first { $0.title == "Previewed" }?.recentPlays == 1)

        try await db.saveGenres(showID: PodcastID.show(feedURL: followedFeed), genreIDs: ["26", "1303"])
        try await db.saveGenres(showID: PodcastID.show(feedURL: previewedFeed), genreIDs: [])
        sources = try db.tasteSources().sorted { $0.title < $1.title }
        #expect(sources[0].genreIDs == ["26", "1303"] && !sources[0].needsLookup)
        #expect(sources[1].genreIDs.isEmpty && !sources[1].needsLookup, "no match is remembered")

        let later = Date().addingTimeInterval(31 * 86400)
        #expect(try db.tasteSources(now: later).first { $0.title == "Previewed" }?.needsLookup == true, "and retried after a month")
    }

    @Test func theShelfDropsFollowedAndDismissedShows() async throws {
        let db = try PodcastDatabase.temporary()
        try await db.replaceRecommendations([pick(1), pick(2), pick(3)])
        func ids() async throws -> [Int] {
            for try await value in db.recommendedShows().values(in: db.pool) { return value.map(\.directoryID) }
            throw CancellationError()
        }
        #expect(try await ids() == [1, 2, 3])

        try await db.dismissRecommendation(feedURL: URL(string: "https://EXAMPLE.com/2.xml")!)
        #expect(try await ids() == [1, 3], "feed URL case and scheme don't matter")

        let feed = ParsedFeed(title: "One", author: "", summary: "", artworkURL: nil, websiteURL: nil, isSerial: false, episodes: [])
        _ = try await db.upsert(feed: feed, feedURL: URL(string: "https://example.com/1.xml")!, validators: nil, follow: true)
        #expect(try await ids() == [3], "following a pick takes it off the shelf")

        let cached = try #require(try db.cachedRecommendationState())
        #expect(cached.signature == "1")
    }
}
