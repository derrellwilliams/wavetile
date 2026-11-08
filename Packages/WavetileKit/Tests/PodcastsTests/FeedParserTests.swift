import Foundation
import Testing
@testable import Podcasts

struct FeedParserTests {
    func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private let episodeXML = "<item><guid>%@</guid><title>%@</title><enclosure url=\"https://example.com/%@.mp3\" type=\"audio/mpeg\"/></item>"

    @Test func aFeedThatEndsNormallyIsComplete() throws {
        let xml = "<rss><channel><title>Show</title>\(String(format: episodeXML, "a", "A", "a"))</channel></rss>"
        let feed = try FeedParser.parse(Data(xml.utf8))
        #expect(feed.isComplete)
        #expect(feed.episodes.count == 1)
    }

    @Test func trailingJunkAfterTheChannelStillCountsAsComplete() throws {
        let xml = "<rss><channel><title>Show</title>\(String(format: episodeXML, "a", "A", "a"))</channel></rss><!-- ads -->  <p>"
        #expect(try FeedParser.parse(Data(xml.utf8)).isComplete)
    }

    /// An unescaped `&` in an old episode ends the parse there; the later episodes were never read.
    @Test func brokenXMLPartwayIsIncomplete() throws {
        let xml = "<rss><channel><title>Show</title>\(String(format: episodeXML, "a", "A", "a"))\(String(format: episodeXML, "b", "Q & A", "b"))\(String(format: episodeXML, "c", "C", "c"))</channel></rss>"
        let feed = try FeedParser.parse(Data(xml.utf8))
        #expect(!feed.isComplete)
        #expect(feed.episodes.map(\.guid) == ["a"])
    }

    @Test func aFeedCutOffBeforeItsTitleIsIncomplete() throws {
        let feed = try FeedParser.parse(Data("<rss><channel><item><guid>a</guid>".utf8))
        #expect(!feed.isComplete)
    }

    /// "Billion laughs": nested internal entities that would expand to gigabytes. The parser must
    /// refuse the expansion (libxml2's amplification limit) rather than build it in memory.
    @Test(.timeLimit(.minutes(1))) func nestedEntitiesDontExpand() throws {
        var dtd = #"<!ENTITY lol0 "lolololololololololololololololololololololololololololololololololololol">"#
        for level in 1 ... 9 {
            dtd += "<!ENTITY lol\(level) \"" + String(repeating: "&lol\(level - 1);", count: 10) + "\">"
        }
        let xml = """
            <?xml version="1.0"?>
            <!DOCTYPE rss [\(dtd)]>
            <rss version="2.0"><channel><title>&lol9;</title>
            <item><guid>a</guid><title>&lol9;</title><enclosure url="https://example.com/a.mp3" type="audio/mpeg"/></item>
            </channel></rss>
            """
        let start = ContinuousClock.now
        let feed = try? FeedParser.parse(Data(xml.utf8))
        #expect(ContinuousClock.now - start < .seconds(5))
        // Fully expanded, the title alone would be 7 GB; anything kept must be small.
        #expect((feed?.title.utf8.count ?? 0) < 1_000_000)
        #expect((feed?.episodes.first?.title.utf8.count ?? 0) < 1_000_000)
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

    @Test func externalEntityCannotReadLocalFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let marker = "private-marker-" + UUID().uuidString
        try Data(marker.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let xml = """
        <!DOCTYPE rss [<!ENTITY secret SYSTEM "\(file.absoluteString)">]>
        <rss><channel><title>&secret;</title><item><guid>a</guid><title>&secret;</title>
        <enclosure url="https://example.com/a.mp3"/></item></channel></rss>
        """
        let feed = try? FeedParser.parse(Data(xml.utf8))
        let title = feed?.title ?? ""
        let episodeTitle = feed?.episodes.first?.title ?? ""
        #expect(!title.contains(marker))
        #expect(!episodeTitle.contains(marker))
    }

    @Test func oversizedEpisodeListIsBounded() throws {
        let items = (0..<3_100).map {
            "<item><guid>\($0)</guid><title>Episode \($0)</title><enclosure url=\"https://example.com/\($0).mp3\"/></item>"
        }.joined()
        let feed = try FeedParser.parse(Data("<rss><channel><title>Large</title>\(items)</channel></rss>".utf8))
        #expect(feed.episodes.count == 3_000)
        #expect(feed.episodes.contains { $0.guid == "0" })
        #expect(!feed.episodes.contains { $0.guid == "3000" })
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
    @Test func oversizedSubscriptionListIsBounded() {
        let outlines = (0..<2_100).map {
            "<outline text=\"Show \($0)\" xmlUrl=\"https://example.com/\($0).xml\"/>"
        }.joined()
        let entries = OPML.parse(Data("<opml><body>\(outlines)</body></opml>".utf8))
        #expect(entries.count == 2_000)
        #expect(entries.first?.title == "Show 0")
        #expect(entries.last?.title == "Show 1999")
    }

    @Test func externalEntityCannotInjectSubscriptions() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(#"<outline text="Injected" xmlUrl="https://example.com/injected.xml"/>"#.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let xml = """
        <!DOCTYPE opml [<!ENTITY injected SYSTEM "\(file.absoluteString)">]>
        <opml><body><outline text="Safe" xmlUrl="https://example.com/safe.xml"/>&injected;</body></opml>
        """
        let entries = OPML.parse(Data(xml.utf8))
        #expect(entries.map(\.title) == ["Safe"])
    }

    @Test(arguments: ["file:///private/test.xml", "javascript:alert(1)", "data:text/xml,test", "wavetile://album/1"])
    func rejectsUnsafeSubscriptionSchemes(_ url: String) {
        let xml = "<opml><body><outline xmlUrl=\"\(url)\"/><outline text=\"Safe\" xmlUrl=\"https://example.com/feed.xml\"/></body></opml>"
        let entries = OPML.parse(Data(xml.utf8))
        #expect(entries.map(\.title) == ["Safe"])
    }

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

struct ShowNotesChapterTests {
    /// Each timestamp style podcasts use, paired with a plain first chapter so it forms a list.
    @Test(arguments: [
        ("05:12 The news", 312.0, "The news"),
        ("[05:12] - The news", 312, "The news"),
        ("(1:02:03) Q&amp;A", 3723, "Q&A"),
        ("• 05:12 – The news", 312, "The news"),
        ("The news (05:12)", 312, "The news"),
        ("The news – 05:12", 312, "The news"),
    ])
    func readsTimestampStyle(line: String, start: Double, title: String) {
        let chapters = ShowNotes.chapters(html: "<p>This week.</p><p>00:00 Intro<br>\(line)</p>")
        #expect(chapters == [Chapter(start: 0, title: "Intro"), Chapter(start: start, title: title)])
    }

    @Test func notesDropTheirTimestampListWhenChaptersShow() {
        let notes = ShowNotes.attributed(html: "<p>A great episode.</p><p>Timestamps:</p><p>00:00 Intro<br>05:12 News</p><p>Sponsored by Acme.</p>")
        let text = String(ShowNotes.removingTimestampLines(from: notes).characters)
        #expect(text == "A great episode.\n\nSponsored by Acme.")
    }

    @Test func needsAnOrderedListOfTwoOrMore() {
        #expect(ShowNotes.chapters(html: "<p>Recorded at 10:30 in the studio</p>").isEmpty)
        #expect(ShowNotes.chapters(html: "<p>12:00 Late</p><p>01:00 Early</p>").isEmpty)
        // The longest increasing list wins; times past the end are dropped.
        let html = "<p>00:00 A<br>10:00 B<br>20:00 C</p><p>05:00 X<br>06:00 Y</p><p>2:00:00 Too late</p>"
        #expect(ShowNotes.chapters(html: html, duration: 3600).map(\.title) == ["A", "B", "C"])
    }
}
