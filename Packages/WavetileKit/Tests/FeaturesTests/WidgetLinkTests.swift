import Foundation
import Testing
@testable import WidgetShared

struct WidgetLinkTests {
    /// Album IDs come from the server; an odd one must still make a valid link, not crash the widget.
    @Test(arguments: ["8f1c2a9e4b7d4e0f9a3b6c5d2e1f0a9b", "with space", "100%", "é", "a?b#c", "../x", "", "emoji🎵"])
    func albumLinksAreAlwaysValid(_ id: String) throws {
        let url = WidgetLink.album(id)
        #expect(url.scheme == "wavetile")
        #expect(url.host() == "album")
        #expect(!url.absoluteString.contains(" "))
    }

    @Test(arguments: ["8f1c2a9e4b7d4e0f9a3b6c5d2e1f0a9b", "with space", "100%", "é", "emoji🎵"])
    func theAppReadsBackTheSameID(_ id: String) {
        #expect(WidgetLink.album(id).lastPathComponent == id)
    }
}
