import Foundation
import GRDB
import Testing
@testable import Podcasts

struct PodcastDatabaseTests {
    let feedURL = URL(string: "https://example.com/feed.xml")!

    func episode(_ guid: String, daysAgo: Double, duration: Double = 3600) -> ParsedEpisode {
        ParsedEpisode(
            guid: guid, title: "Episode \(guid)", summary: "", notesHTML: "",
            publishedAt: Date().addingTimeInterval(-daysAgo * 86400), duration: duration,
            audioURL: URL(string: "https://cdn.example.com/\(guid).mp3")!, mimeType: "audio/mpeg", byteLength: nil,
            artworkURL: nil, season: nil, number: nil, episodeType: nil, chaptersURL: nil
        )
    }

    func feed(_ episodes: [ParsedEpisode]) -> ParsedFeed {
        ParsedFeed(title: "Show", author: "Host", summary: "", artworkURL: nil, websiteURL: nil, isSerial: false, episodes: episodes)
    }

    func id(_ guid: String) -> String { PodcastID.episode(feedURL: feedURL, guid: guid) }

    @Test func upsertKeepsListeningStateAndReportsNewEpisodes() async throws {
        let db = try PodcastDatabase.temporary()
        let first = try await db.upsert(feed: feed([episode("a", daysAgo: 2)]), feedURL: feedURL, validators: nil, follow: true)
        #expect(first.newEpisodeIDs == [id("a")])
        #expect(first.show.isFollowed)
        try await db.savePosition(episodeID: id("a"), position: 600, duration: 3600)

        let second = try await db.upsert(feed: feed([episode("b", daysAgo: 0), episode("a", daysAgo: 2)]), feedURL: feedURL, validators: nil, follow: false)
        #expect(second.newEpisodeIDs == [id("b")])
        #expect(second.show.isFollowed, "refreshing never unfollows")
        let a = try #require(try db.episodeNow(id: id("a")))
        #expect(a.episode.position == 600)
    }

    @Test func episodesLeavingTheFeedAreKeptOnlyWithUserState() async throws {
        let db = try PodcastDatabase.temporary()
        _ = try await db.upsert(feed: feed([episode("a", daysAgo: 3), episode("b", daysAgo: 2), episode("c", daysAgo: 1)]), feedURL: feedURL, validators: nil, follow: true)
        try await db.setSaved(episodeID: id("a"), true)
        try await db.enqueue(episodeID: id("b"), atFront: false)
        _ = try await db.upsert(feed: feed([episode("d", daysAgo: 0)]), feedURL: feedURL, validators: nil, follow: false)
        #expect(try db.episodeNow(id: id("a")) != nil)
        #expect(try db.episodeNow(id: id("b")) != nil)
        #expect(try db.episodeNow(id: id("c")) == nil)
    }

    @Test func finishingNearTheEndMarksPlayedAndLeavesUpNext() async throws {
        let db = try PodcastDatabase.temporary()
        _ = try await db.upsert(feed: feed([episode("a", daysAgo: 1)]), feedURL: feedURL, validators: nil, follow: true)
        try await db.enqueue(episodeID: id("a"), atFront: false)
        let midway = try await db.savePosition(episodeID: id("a"), position: 1800, duration: 3600)
        #expect(!midway)
        let finished = try await db.savePosition(episodeID: id("a"), position: 3590, duration: 3600)
        #expect(finished)
        let a = try #require(try db.episodeNow(id: id("a")))
        #expect(a.episode.isPlayed)
        #expect(a.episode.position == 0)
        #expect(try db.queueNow().isEmpty)
    }

    @Test func tinyPositionsDontCountAsInProgress() async throws {
        let db = try PodcastDatabase.temporary()
        _ = try await db.upsert(feed: feed([episode("a", daysAgo: 1)]), feedURL: feedURL, validators: nil, follow: true)
        try await db.savePosition(episodeID: id("a"), position: 3, duration: 3600)
        #expect(try db.episodeNow(id: id("a"))?.episode.isInProgress == false)
    }

    @Test func upNextOrdersFrontAndBack() async throws {
        let db = try PodcastDatabase.temporary()
        _ = try await db.upsert(feed: feed([episode("a", daysAgo: 3), episode("b", daysAgo: 2), episode("c", daysAgo: 1)]), feedURL: feedURL, validators: nil, follow: true)
        try await db.enqueue(episodeID: id("a"), atFront: false)
        try await db.enqueue(episodeID: id("b"), atFront: false)
        try await db.enqueue(episodeID: id("c"), atFront: true)
        #expect(try db.queueNow().map(\.episode.guid) == ["c", "a", "b"])
        try await db.setQueue([id("b"), id("c")])
        #expect(try db.queueNow().map(\.episode.guid) == ["b", "c"])
    }

    @Test func unfollowedPreviewsAreCleanedUp() async throws {
        let db = try PodcastDatabase.temporary()
        _ = try await db.upsert(feed: feed([episode("a", daysAgo: 1)]), feedURL: feedURL, validators: nil, follow: false)
        let other = URL(string: "https://example.com/other.xml")!
        _ = try await db.upsert(feed: feed([episode("x", daysAgo: 1)]), feedURL: other, validators: nil, follow: false)
        try await db.savePosition(episodeID: PodcastID.episode(feedURL: other, guid: "x"), position: 120, duration: 3600)
        _ = try await db.removeUnfollowedShows()
        #expect(try db.showNow(id: PodcastID.show(feedURL: feedURL)) == nil)
        #expect(try db.showNow(id: PodcastID.show(feedURL: other)) != nil, "kept: it has a resume point")
    }

    @Test func autoDownloadPicksNewestUnplayedPerShow() async throws {
        let db = try PodcastDatabase.temporary()
        let result = try await db.upsert(feed: feed([episode("a", daysAgo: 3), episode("b", daysAgo: 2), episode("c", daysAgo: 1)]), feedURL: feedURL, validators: nil, follow: true)
        #expect(try db.autoDownloadCandidates(perShow: 2).isEmpty, "off by default")
        try await db.updateShow(id: result.show.id) { $0.autoDownload = true }
        try await db.setPlayed(episodeIDs: [id("c")], true)
        #expect(Set(try db.autoDownloadCandidates(perShow: 2)) == [id("b")])
    }

    @Test func remoteStateAppliesNewerPositionsAndFinishes() async throws {
        let db = try PodcastDatabase.temporary()
        _ = try await db.upsert(feed: feed([episode("a", daysAgo: 2), episode("b", daysAgo: 1)]), feedURL: feedURL, validators: nil, follow: true)
        try await db.savePosition(episodeID: id("a"), position: 100, duration: 3600)
        try await db.applyRemote(
            positions: [id("a"): (position: 900, updated: Date().addingTimeInterval(60))],
            played: [id("b"): Date()]
        )
        #expect(try db.episodeNow(id: id("a"))?.episode.position == 900)
        #expect(try db.episodeNow(id: id("b"))?.episode.isPlayed == true)
    }
}

struct PodcastSyncTests {
    let a = URL(string: "https://a.com/feed")!
    let b = URL(string: "https://b.com/feed")!
    let secret = URL(string: "https://patreon.com/rss/x?auth=TOKEN")!

    @Test func roundTripsThroughCustomPrefs() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let state = PodcastSyncState(
            enabled: true, enabledUpdated: now, subscriptions: [a, secret], subscriptionsUpdated: now,
            positions: ["e1": .init(seconds: 12.5, updated: now)], played: ["e2": Date()]
        )
        let decoded = PodcastSyncState(customPrefs: state.customPrefs)
        #expect(decoded.enabled == true)
        #expect(decoded.subscriptions == [a], "private feeds never leave the device")
        #expect(decoded.positions["e1"]?.seconds == 12.5)
        #expect(decoded.played.keys.contains("e2"))
    }

    @Test func newerRemoteSubscriptionsWinButKeepPrivateFeeds() {
        let local = PodcastSyncState(subscriptions: [a, secret], subscriptionsUpdated: Date(timeIntervalSince1970: 100))
        let remote = PodcastSyncState(subscriptions: [b], subscriptionsUpdated: Date(timeIntervalSince1970: 200))
        #expect(local.merged(withRemote: remote).subscriptions == [b, secret])
        #expect(remote.merged(withRemote: local).subscriptions == [b], "older remote list is ignored")
    }

    @Test func positionsMergePerEpisodeAndFinishesWin() {
        let t1 = Date(timeIntervalSince1970: 100), t2 = Date(timeIntervalSince1970: 200)
        let local = PodcastSyncState(positions: ["x": .init(seconds: 10, updated: t2), "y": .init(seconds: 50, updated: t1)])
        let remote = PodcastSyncState(positions: ["x": .init(seconds: 99, updated: t1), "z": .init(seconds: 5, updated: t1)], played: ["y": t2])
        let merged = local.merged(withRemote: remote)
        #expect(merged.positions["x"]?.seconds == 10)
        #expect(merged.positions["z"]?.seconds == 5)
        #expect(merged.positions["y"] == nil)
        #expect(merged.played["y"] == t2)
    }

    @Test func privateFeedDetection() {
        #expect(PodcastSyncState.isPrivate(secret))
        #expect(PodcastSyncState.isPrivate(URL(string: "https://user:pass@host.com/feed")!))
        #expect(!PodcastSyncState.isPrivate(a))
    }
}

struct PodcastSecurityTests {
    @Test func podcastRequestsCarryNoCredentials() {
        let config = PodcastNetwork.session.configuration
        let headers = config.httpAdditionalHeaders as? [String: String] ?? [:]
        #expect(headers.keys.map { $0.lowercased() }.allSatisfy { $0 != "authorization" && $0 != "x-emby-token" })
        #expect(config.httpShouldSetCookies == false)
        #expect(config.urlCredentialStorage == nil)
    }

    @Test func chaptersJSONParses() throws {
        let json = #"{"version":"1.2","chapters":[{"startTime":60,"title":"Two"},{"startTime":0,"title":"One"},{"startTime":90,"toc":false}]}"#
        let chapters = try ChapterLoader.parseJSON(Data(json.utf8))
        #expect(chapters.map(\.title) == ["One", "Two"])
    }
}
