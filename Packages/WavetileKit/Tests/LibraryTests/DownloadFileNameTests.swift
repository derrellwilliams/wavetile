import Foundation
import Testing
@testable import Downloads

struct DownloadFileNameTests {
    private func response(mime: String?, url: String = "https://music.example.com/Audio/1/universal") -> URLResponse {
        URLResponse(url: URL(string: url)!, mimeType: mime, expectedContentLength: 0, textEncodingName: nil)
    }

    @Test func keepsJellyfinIDs() {
        let name = DownloadManager.fileName(trackID: "8f1c2a9e4b7d4e0f9a3b6c5d2e1f0a9b", response: response(mime: "audio/flac"))
        #expect(name == "8f1c2a9e4b7d4e0f9a3b6c5d2e1f0a9b.flac")
    }

    @Test(arguments: ["../../Library/Preferences/x", "/etc/passwd", "a/../b", "..", ""])
    func hostileIDsStayInTheFolder(_ trackID: String) {
        let name = DownloadManager.fileName(trackID: trackID, response: response(mime: "audio/mpeg"))
        #expect(!name.contains("/"))
        #expect(!name.hasPrefix("."))
    }

    @Test func cleansExtensionFromTheURL() {
        let name = DownloadManager.fileName(trackID: "abc", response: response(mime: nil, url: "https://h/x.fl%2F..ac"))
        #expect(!name.contains("/"))
        #expect(name.hasPrefix("abc."))
    }
}
