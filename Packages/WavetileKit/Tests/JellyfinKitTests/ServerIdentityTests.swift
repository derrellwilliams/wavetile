import Foundation
import Testing
@testable import JellyfinKit

/// Answers `System/Info/Public` with a fixed server ID, keyed by host so suites can run in parallel.
final class PublicInfoStub: URLProtocol, @unchecked Sendable {
    static let ids: [String: String] = ["192.168.50.1": "ABCDEF12-3456-7890-abcd-ef1234567890", "192.168.50.2": ""]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let id = Self.ids[request.url?.host() ?? ""] ?? "other"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"Id":"\#(id)"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

struct ServerIdentityTests {
    private let home = URL(string: "http://192.168.50.1:8096")!
    private let savedID = "abcdef1234567890abcdef1234567890"

    @Test func matchingIDReleasesTheToken() async {
        let identity = ServerIdentity(protocolClasses: [PublicInfoStub.self])
        identity.register(home, serverID: savedID)
        #expect(await identity.confirmToken(to: home.appending(path: "Items")))
        #expect(identity.allowsToken(to: home))
    }

    @Test func anotherServerAtTheAddressGetsNoToken() async {
        let identity = ServerIdentity(protocolClasses: [PublicInfoStub.self])
        identity.register(home, serverID: "ffffffffffffffffffffffffffffffff")
        #expect(await identity.confirmToken(to: home) == false)
    }

    @Test func emptyIDsNeverMatch() async {
        // Neither a session saved without an ID nor a server that answers with a blank one.
        let identity = ServerIdentity(protocolClasses: [PublicInfoStub.self])
        identity.register(home, serverID: "")
        #expect(await identity.confirmToken(to: home) == false)
        let blank = URL(string: "http://192.168.50.2:8096")!
        identity.register(blank, serverID: "")
        #expect(await identity.confirmToken(to: blank) == false)
        #expect(!ServerIdentity.isSameServer("", ""))
    }

    @Test func registeringAgainAsksAgain() async {
        // Sign out, change networks, sign in: the answer from the old network doesn't carry over.
        let identity = ServerIdentity(protocolClasses: [PublicInfoStub.self])
        identity.register(home, serverID: savedID)
        #expect(await identity.confirmToken(to: home))
        identity.register(home, serverID: savedID)
        #expect(!identity.allowsToken(to: home))
    }

    private let lan = URL(string: "http://192.168.1.5:8096")!

    @Test func httpsNeverWaits() async {
        let identity = ServerIdentity()
        let url = URL(string: "https://music.example.com")!
        identity.register(url, serverID: "abc")
        #expect(identity.allowsToken(to: url.appending(path: "Items")))
        #expect(await identity.confirmToken(to: url))
    }

    @Test func unknownHTTPServerPasses() {
        // Signing in: nothing to check the address against yet.
        #expect(ServerIdentity().allowsToken(to: lan.appending(path: "Users/AuthenticateByName")))
    }

    @Test func signedInHTTPServerWaitsForItsID() {
        let identity = ServerIdentity()
        identity.register(lan, serverID: "abc")
        #expect(!identity.allowsToken(to: lan.appending(path: "Items")))
        #expect(!identity.allowsToken(to: URL(string: "http://192.168.1.5:8096/Audio/1/universal")!))
    }

    @Test func noAnswerKeepsTheToken() async {
        let identity = ServerIdentity()
        let closed = URL(string: "http://127.0.0.1:1")!
        identity.register(closed, serverID: "abc")
        #expect(await identity.confirmToken(to: closed.appending(path: "Items")) == false)
        identity.networkChanged()
        #expect(!identity.allowsToken(to: closed))
    }
}
