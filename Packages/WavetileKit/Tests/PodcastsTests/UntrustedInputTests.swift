import Foundation
import Testing
@testable import Podcasts

/// Numbers and text that a feed or the Jellyfin preferences record can carry: none of them may
/// crash the app or stall it, because both are read at launch with nobody to vet them.
struct UntrustedInputTests {
    // MARK: Sync preferences

    @Test(arguments: ["inf", "-inf", "nan", "1e300", "-1e300"])
    func oddTimestampsInPreferencesNeverCrashTheSync(_ stamp: String) {
        // A newer-looking remote timestamp is adopted by the merge and written back out; turning
        // it into an Int used to trap for anything that isn't a sane date.
        let remote = PodcastSyncState(customPrefs: [
            "enabled": "1", "enabledUpdated": stamp,
            "subs": #"["https://example.com/feed.xml"]"#, "subsUpdated": stamp,
        ])
        let merged = PodcastSyncState().merged(withRemote: remote)
        // Writing the merged record back used to trap; a date like that now counts as no date,
        // so the remote list and flag lose to this device's.
        let written = merged.customPrefs
        #expect(merged.subscriptions.isEmpty)
        #expect(merged.enabled == nil)
        #expect(written["subsUpdated"] == nil)
    }

    @Test func plausibleTimestampsStillMerge() {
        let remote = PodcastSyncState(customPrefs: [
            "enabled": "1", "enabledUpdated": "1700000000",
            "subs": #"["https://example.com/feed.xml"]"#, "subsUpdated": "1700000000",
        ])
        let merged = PodcastSyncState().merged(withRemote: remote)
        #expect(merged.subscriptions.map(\.host) == ["example.com"])
        #expect(merged.customPrefs["subsUpdated"] == "1700000000")
    }

    @Test func positionsInPreferencesAreSaneTimes() {
        let prefs = PodcastSyncState(customPrefs: [
            "pos": #"{"a":[120.5,1700000000],"b":[1e300,1700000000],"c":[-5,1700000000],"d":[90000000,1700000000]}"#,
        ])
        #expect(prefs.positions.keys.sorted() == ["a"])
    }

    // MARK: Feed durations

    @Test(arguments: ["1e30", "99999999999999999999999", "1e308", "inf", "nan", "-5", "1:2:3:4", "604801"])
    func absurdDurationsAreDropped(_ text: String) {
        #expect(FeedParser.duration(text) == nil)
    }

    @Test func realDurationsSurvive() {
        #expect(FeedParser.duration("3723") == 3723)
        #expect(FeedParser.duration("1:02:03") == 3723)
        #expect(FeedParser.duration("604800") == 604_800)  // a week: long audiobook feeds exist
    }

    // MARK: Show notes

    @Test func paddedShowNotesLinesDontStallChapterDetection() {
        // `&nbsp;` decodes to a space after whitespace is collapsed, so a line can be a couple of
        // hundred spaces; the chapter patterns then backtrack hard on every such line.
        let line = "a" + String(repeating: "&nbsp;", count: 190) + "x<br>"
        let html = String(repeating: line, count: 80)
        let started = ContinuousClock.now
        _ = ShowNotes.chapters(html: html)
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test func entityPaddingCollapsesLikeAnyOtherWhitespace() {
        let text = String(ShowNotes.attributed(html: "one&nbsp;&nbsp;&nbsp;two").characters)
        #expect(text == "one two")
    }

    // MARK: Chapters

    @Test func chaptersWithTheSameStartAreOneRow() throws {
        // `Chapter.id` is the start time; two rows with one ID confuse the list.
        let json = #"{"chapters":[{"startTime":0,"title":"A"},{"startTime":0,"title":"B"},{"startTime":30,"title":"C"}]}"#
        let chapters = try ChapterLoader.parseJSON(Data(json.utf8))
        #expect(chapters.map(\.title) == ["A", "C"])
    }

    @Test func chapterListsAreCapped() throws {
        let entries = (0 ..< 5000).map { #"{"startTime":\#($0),"title":"c"}"# }.joined(separator: ",")
        let chapters = try ChapterLoader.parseJSON(Data(#"{"chapters":[\#(entries)]}"#.utf8))
        #expect(chapters.count == ChapterLoader.maxChapters)
    }

    // MARK: Feed URLs

    @Test func feedsCantPointTheAppAtLocalHosts() {
        // Audio and images may load over plain HTTP, so a feed naming a LAN address would have
        // the phone send that device a request.
        for local in ["http://192.168.1.1/reboot", "http://10.0.0.5/x.mp3", "http://printer.local/x", "http://localhost:8096/x", "http://[fd00::1]/x"] {
            #expect(FeedParser.webURL(local) == nil, "\(local)")
        }
        #expect(FeedParser.webURL("http://example.com/x.mp3") != nil)
        #expect(FeedParser.webURL("https://example.com/x.mp3") != nil)
        // HTTPS can't reach a LAN device unnoticed: the certificate wouldn't match.
        #expect(FeedParser.webURL("https://192.168.1.1/x.mp3") != nil)
    }

    // MARK: Episode downloads

    @Test func downloadSizeIsCapped() {
        #expect(!EpisodeDownloadManager.exceedsLimit(written: 300 * 1024 * 1024))
        #expect(EpisodeDownloadManager.exceedsLimit(written: EpisodeDownloadManager.maxBytes + 1))
    }
}
