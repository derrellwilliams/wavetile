import Foundation
import Testing
@testable import Podcasts

struct FeedParserTests {
    func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func parsesChannelAndEpisodes() throws {
        let feed = try FeedParser.parse(fixture("feed.xml"))
        #expect(feed.title == "Test Cast & Friends")
        #expect(feed.author == "Jane Host")
        #expect(feed.isSerial)
        #expect(feed.summary == "A show about tests.")
        #expect(feed.artworkURL == URL(string: "https://example.com/art.jpg"))
        #expect(feed.websiteURL == URL(string: "https://example.com"))
        // Items without audio, or with a non-web enclosure, are skipped.
        #expect(feed.episodes.map(\.guid) == ["ep-2", "ep-1"])
    }

    @Test func parsesEpisodeFields() throws {
        let episode = try #require(try FeedParser.parse(fixture("feed.xml")).episodes.first)
        #expect(episode.title == "Episode Two")
        #expect(episode.duration == 3723)
        #expect(episode.number == 2)
        #expect(episode.season == 1)
        #expect(episode.byteLength == 12345)
        #expect(episode.mimeType == "audio/mpeg")
        #expect(episode.artworkURL == URL(string: "https://example.com/ep2.jpg"))
        #expect(episode.chaptersURL == URL(string: "https://example.com/ep2-chapters.json"))
        #expect(episode.summary == "Short & sweet summary")
        // Show notes prefer content:encoded.
        #expect(episode.notesHTML.contains("Intro at 0:30"))
        #expect(episode.publishedAt == Date(timeIntervalSince1970: 1_792_483_200))
    }

    @Test func secondEpisodeUsesFallbacks() throws {
        let episode = try FeedParser.parse(fixture("feed.xml")).episodes[1]
        #expect(episode.duration == 2703)
        #expect(episode.summary == "First!")
        #expect(episode.audioURL.scheme == "http")
        #expect(episode.publishedAt != nil)
    }

    @Test func externalEntitiesAreNeverResolved() throws {
        let feed = try? FeedParser.parse(fixture("feed-xxe.xml"))
        let text = [feed?.title ?? "", feed?.episodes.first?.title ?? ""].joined()
        #expect(!text.contains("localhost"))
    }

    @Test func rejectsNonFeeds() {
        #expect(throws: FeedError.notAFeed) { try FeedParser.parse(Data("<html><body>Hi</body></html>".utf8)) }
    }

    @Test(arguments: [
        ("3723", 3723.0), ("62:03", 3723), ("1:02:03", 3723), ("90.5", 90.5),
    ])
    func durations(text: String, seconds: Double) {
        #expect(FeedParser.duration(text) == seconds)
    }

    @Test func badDurationsAreNil() {
        #expect(FeedParser.duration("") == nil)
        #expect(FeedParser.duration("abc") == nil)
        #expect(FeedParser.duration("1:2:3:4") == nil)
    }

    @Test func onlyWebURLsSurvive() {
        #expect(FeedParser.webURL("https://a.com/x.mp3") != nil)
        #expect(FeedParser.webURL("javascript:alert(1)") == nil)
        #expect(FeedParser.webURL("file:///etc/passwd") == nil)
        #expect(FeedParser.webURL("wavetile://album/1") == nil)
    }
}

struct ShowNotesTests {
    @Test func dropsScriptsAndUnsafeLinks() {
        let notes = ShowNotes.attributed(html: #"<p>Hi <script>alert(1)</script><a href="javascript:alert(1)">bad</a> <a href="https://ok.com">good</a></p>"#)
        let text = String(notes.characters)
        #expect(!text.contains("alert"))
        let links = notes.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://ok.com")!])
    }

    @Test func keepsParagraphsListsAndEmphasis() {
        let notes = ShowNotes.attributed(html: "<p>One</p><p><b>Two</b></p><ul><li>A</li><li>B</li></ul>")
        #expect(String(notes.characters) == "One\n\nTwo\n\n• A\n• B")
        #expect(notes.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
    }

    @Test func timestampsBecomeSeekLinks() throws {
        let notes = ShowNotes.attributed(html: "Topics: 1:02:03 intro, 12:34 news")
        let links = notes.runs.compactMap(\.link)
        #expect(links.compactMap(ShowNotes.seekTime) == [3723, 754])
    }

    @Test func decodesEntities() {
        #expect(ShowNotes.decodeEntities("A &amp; B &#8217; &#x2014; &bogus;") == "A & B ’ — &bogus;")
    }
}

struct OPMLTests {
    @Test func parsesDedupesAndFilters() throws {
        let url = try #require(Bundle.module.url(forResource: "subscriptions", withExtension: "opml", subdirectory: "Fixtures"))
        let entries = OPML.parse(try Data(contentsOf: url))
        #expect(entries.map(\.feedURL.absoluteString) == ["https://feeds.simplecast.com/6HKOhNgS", "https://example.com/feed.xml"])
        #expect(entries.first?.title == "Hard Fork")
    }

    @Test func exportRoundTrips() throws {
        let show = ShowRecord(
            id: "x", feedURL: URL(string: "https://example.com/feed?a=1&b=2")!, title: "Tom & Jerry's <Show>",
            author: "", summary: "", artworkURL: nil, websiteURL: nil, isSerial: false
        )
        let entries = OPML.parse(Data(OPML.export([show]).utf8))
        #expect(entries.first?.title == "Tom & Jerry's <Show>")
        #expect(entries.first?.feedURL == show.feedURL)
    }
}

struct PodcastIDTests {
    @Test func httpAndHTTPSFeedsShareIDs() {
        let http = URL(string: "http://Feeds.Example.com/show")!
        let https = URL(string: "https://feeds.example.com/show")!
        #expect(PodcastID.show(feedURL: http) == PodcastID.show(feedURL: https))
        #expect(PodcastID.episode(feedURL: http, guid: "g") == PodcastID.episode(feedURL: https, guid: "g"))
        #expect(PodcastID.episode(feedURL: https, guid: "g") != PodcastID.episode(feedURL: https, guid: "h"))
    }

    @Test func insecureSchemesUpgrade() {
        #expect(PodcastNetwork.secure(URL(string: "http://a.com/f")!)?.scheme == "https")
        #expect(PodcastNetwork.secure(URL(string: "feed://a.com/f")!)?.absoluteString == "https://a.com/f")
        #expect(PodcastNetwork.secure(URL(string: "file:///etc/passwd")!) == nil)
    }
}
