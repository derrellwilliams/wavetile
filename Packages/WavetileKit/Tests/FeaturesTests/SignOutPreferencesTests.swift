import Foundation
import Testing
@testable import Features

/// What an account keeps in UserDefaults (hidden Recently Played albums, welcome-card visits,
/// cover shuffles) leaves the device at sign-out with its databases and files.
@Suite(.serialized) struct SignOutPreferencesTests {
    @Test func homePreferencesAreClearedForThatAccountOnly() {
        let defaults = UserDefaults.standard
        defaults.set(["album-1"], forKey: "hiddenRecentlyPlayed.passsix-a")
        defaults.set(1, forKey: "welcomeVisits.passsix-a")
        defaults.set(["album-2"], forKey: "hiddenRecentlyPlayed.passsix-b")
        defer {
            for key in ["hiddenRecentlyPlayed.passsix-a", "welcomeVisits.passsix-a", "hiddenRecentlyPlayed.passsix-b"] {
                defaults.removeObject(forKey: key)
            }
        }
        HomeModel.clearStored(userID: "passsix-a")
        #expect(defaults.stringArray(forKey: "hiddenRecentlyPlayed.passsix-a") == nil)
        #expect(defaults.object(forKey: "welcomeVisits.passsix-a") == nil)
        #expect(defaults.stringArray(forKey: "hiddenRecentlyPlayed.passsix-b") == ["album-2"])
    }

    @Test func coverShufflesAreClearedForThatAccount() {
        let defaults = UserDefaults.standard
        defaults.set(["playlist-1": 3], forKey: "coverShuffles.server-x.passsix-a")
        defer { defaults.removeObject(forKey: "coverShuffles.server-x.passsix-a") }
        LibraryStore.clearStored(serverID: "server-x", userID: "passsix-a")
        #expect(defaults.dictionary(forKey: "coverShuffles.server-x.passsix-a") == nil)
    }
}
