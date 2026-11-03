import Foundation
import Testing
@testable import JellyfinKit

struct ServerIdentityTests {
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
