import Foundation
import Testing
@testable import JellyfinKit

struct RedirectGuardTests {
    private func redirect(from original: String, to target: String) -> URLRequest? {
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
        #expect(redirect(from: original, to: target)?.value(forHTTPHeaderField: "Authorization") != nil)
    }

    @Test(arguments: [
        ("https://music.example.com/Items", "https://cdn.example.net/file.flac"),
        ("https://music.example.com/Items", "http://music.example.com/Items"),
        ("https://music.example.com/Items", "https://music.example.com:8920/Items"),
        ("http://192.168.1.5:8096/Items", "http://192.168.1.6:8096/Items"),
    ])
    func dropsTokenOffOrigin(_ original: String, _ target: String) {
        let request = redirect(from: original, to: target)
        #expect(request != nil)
        #expect(request?.value(forHTTPHeaderField: "Authorization") == nil)
    }
    @Test(arguments: ["POST", "PUT", "PATCH", "DELETE"])
    func refusesCrossOriginWrites(_ method: String) {
        var request = URLRequest(url: URL(string: "https://other.example/login")!)
        request.httpMethod = method
        request.httpBody = Data("password=secret".utf8)
        #expect(RedirectGuard.request(request, redirectedFrom: URL(string: "https://music.example/login")) == nil)
    }

    @Test
    func preservesSameOriginLogin() {
        var request = URLRequest(url: URL(string: "https://music.example/new-login")!)
        request.httpMethod = "POST"
        request.httpBody = Data("password=secret".utf8)
        #expect(RedirectGuard.request(request, redirectedFrom: URL(string: "https://music.example/login")) == request)
    }

    @Test
    func refusesBodyOnReadAndUnknownOrigin() {
        var request = URLRequest(url: URL(string: "https://other.example/file")!)
        #expect(RedirectGuard.request(request, redirectedFrom: nil) == nil)
        request.httpBody = Data("secret".utf8)
        #expect(RedirectGuard.request(request, redirectedFrom: URL(string: "https://music.example/file")) == nil)
        request.httpBody = nil
        request.httpBodyStream = InputStream(data: Data("secret".utf8))
        #expect(RedirectGuard.request(request, redirectedFrom: URL(string: "https://music.example/file")) == nil)
    }

    @Test(arguments: [
        ("https://music.example.com/Audio/1", "https://music.example.com/Audio/1", false),
        ("https://music.example.com/Audio/1", "https://MUSIC.example.com:443/proxy/1", false),
        ("https://music.example.com/Audio/1", "https://cdn.example.net/1.flac", true),
        ("https://music.example.com/Audio/1", "http://music.example.com/Audio/1", true),
        ("http://192.168.1.5:8096/Audio/1", "http://192.168.1.6:8096/Audio/1", true),
    ])
    func detectsBackgroundRedirectOffOrigin(_ requested: String, _ ended: String, _ expected: Bool) {
        #expect(RedirectGuard.leftOrigin(requested: URL(string: requested), ended: URL(string: ended)) == expected)
    }

    @Test
    func unknownURLsAreNotTreatedAsRedirects() {
        #expect(!RedirectGuard.leftOrigin(requested: nil, ended: URL(string: "https://a.example")))
        #expect(!RedirectGuard.leftOrigin(requested: URL(string: "https://a.example"), ended: nil))
    }
}
