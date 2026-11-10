import Foundation
import JellyfinKit
import Testing
@testable import Playback

/// What the system and the network hand the player: remote-command times, and network changes
/// while nothing carries a token.
@MainActor
struct RemoteInputTests {
    private func player(_ address: String) -> AudioPlayer {
        let auth = AuthService(identity: ClientIdentity(clientName: "Wavetile", version: "1", deviceName: "Test", deviceID: "device"))
        let session = ServerSession(serverURL: URL(string: address)!, serverID: "srv", serverName: "Home", userID: "u1", userName: "Test")
        return AudioPlayer(library: LibraryClient(session: session, token: "tok", auth: auth))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func remoteSeeksToNonNumbersAreIgnored(_ seconds: Double) {
        // Bluetooth and other remote controls send positions as they please; an invalid time raises
        // inside AVFoundation.
        let player = player("https://music.example")
        player.seek(to: seconds)
        #expect(player.currentTime == 0)
    }

    @Test func aNetworkChangeWithNothingStreamingDoesNothing() {
        // Plain HTTP, nothing loaded: there is no token header to drop, so no reload is started.
        let player = player("http://192.168.1.5:8096")
        player.networkChanged()
        player.enteredForeground()
        #expect(!player.hasQueue)
        #expect(player.offlineNotice == nil)
    }
}
