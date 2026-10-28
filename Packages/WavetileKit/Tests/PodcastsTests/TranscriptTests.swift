import Foundation
import Testing
@testable import Podcasts

struct TranscriptTests {
    @Test func parsesPeopleAndPicksTheTimedTranscript() throws {
        let xml = """
        <rss xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel>
          <title>Show</title>
          <podcast:person role="host" img="https://example.com/jane.jpg">Jane Host</podcast:person>
          <item>
            <title>One</title><guid>1</guid>
            <enclosure url="https://example.com/1.mp3" type="audio/mpeg"/>
            <podcast:transcript url="https://example.com/1.txt" type="text/plain"/>
            <podcast:transcript url="https://example.com/1.vtt" type="text/vtt"/>
            <podcast:person role="Guest" href="https://example.com/sam">Sam Guest</podcast:person>
          </item>
        </channel></rss>
        """
        let feed = try FeedParser.parse(Data(xml.utf8))
        #expect(feed.people == [PodcastPerson(name: "Jane Host", imageURL: URL(string: "https://example.com/jane.jpg"))])
        let episode = try #require(feed.episodes.first)
        #expect(episode.people == [PodcastPerson(name: "Sam Guest", role: "guest", href: URL(string: "https://example.com/sam"))])
        #expect(episode.transcriptURL == URL(string: "https://example.com/1.vtt"))
        #expect(episode.transcriptType == "text/vtt")
    }

    @Test func joinsVTTCuesIntoParagraphsBySpeaker() {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:03.000
        <v Jane>Welcome to the show.

        00:00:03.000 --> 00:00:05.000
        <v Jane>Today we talk tests.

        00:01:02.500 --> 00:01:04.000
        <v Sam>Thanks for having me.
        """
        let paragraphs = Transcript.parse(vtt, type: "text/vtt")
        #expect(paragraphs.map(\.text) == ["Welcome to the show. Today we talk tests.", "Thanks for having me."])
        #expect(paragraphs.map(\.speaker) == ["Jane", "Sam"])
        #expect(paragraphs.map(\.start) == [1, 62.5])
    }

    @Test func readsSRTAndJSON() {
        let srt = "1\n00:00:02,000 --> 00:00:04,000\nHello there.\n\n2\n00:00:04,000 --> 00:00:06,000\nGeneral Kenobi."
        #expect(Transcript.parse(srt, type: "application/x-subrip").first?.text == "Hello there. General Kenobi.")
        let json = #"{"segments":[{"speaker":"A","startTime":1.5,"body":"Hi."},{"speaker":"B","startTime":3,"body":"Hey."}]}"#
        #expect(Transcript.parse(json, type: "application/json").map(\.speaker) == ["A", "B"])
    }
}
