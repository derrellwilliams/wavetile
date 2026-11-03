import Foundation
import Testing
@testable import JellyfinKit

struct RedirectGuardTests {
    private func redirect(from original: String, to target: String) -> URLRequest {
        var request = URLRequest(url: URL(string: target)!)
        request.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        return RedirectGuard.request(request, redirectedFrom: URL(string: original)!)
    }

    @Test(arguments: [
        ("https://music.example.com/Items", "https://music.example.com/jellyfin/Items"),
        ("https://music.example.com/Items", "https://MUSIC.example.com:443/Items"),
        ("http://192.168.1.5:8096/Items", "http://192.168.1.5:8096/web"),
    ])
    func keepsTokenOnSameOrigin(_ original: String, _ target: String) {
        #expect(redirect(from: original, to: target).value(forHTTPHeaderField: "Authorization") != nil)
    }

    @Test(arguments: [
        ("https://music.example.com/Items", "https://cdn.example.net/file.flac"),
        ("https://music.example.com/Items", "http://music.example.com/Items"),
        ("https://music.example.com/Items", "https://music.example.com:8920/Items"),
        ("http://192.168.1.5:8096/Items", "http://192.168.1.6:8096/Items"),
    ])
    func dropsTokenOffOrigin(_ original: String, _ target: String) {
        #expect(redirect(from: original, to: target).value(forHTTPHeaderField: "Authorization") == nil)
    }
}
