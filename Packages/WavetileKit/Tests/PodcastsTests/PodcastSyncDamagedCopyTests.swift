import Foundation
import Testing
@testable import Podcasts

struct PodcastSyncDamagedCopyTests {
    let a = URL(string: "https://example.com/a.xml")!
    let b = URL(string: "https://example.com/b.xml")!

    func local() -> PodcastSyncState {
        PodcastSyncState(subscriptions: [a, b], subscriptionsUpdated: Date(timeIntervalSince1970: 100))
    }

    @Test func aNewerReadableRemoteListStillWins() {
        let remote = PodcastSyncState(customPrefs: ["subs": "[\"https://example.com/b.xml\"]", "subsUpdated": "200"])
        let merged = local().merged(withRemote: remote)
        #expect(merged.subscriptions == [b])
        #expect(merged.subscriptionsUpdated == Date(timeIntervalSince1970: 200))
    }

    @Test(arguments: [
        ["subs": "[\"https://example.com/b.xml\"", "subsUpdated": "200"],  // truncated JSON
        ["subs": "not json", "subsUpdated": "200"],
        ["subs": "{\"a\": 1}", "subsUpdated": "200"],  // wrong shape
        ["subsUpdated": "200"],  // list missing
    ])
    func anUnreadableRemoteListIsNotAnEmptyOne(prefs: [String: String]) {
        let remote = PodcastSyncState(customPrefs: prefs)
        #expect(remote.subscriptionsUpdated == nil)
        let merged = local().merged(withRemote: remote)
        #expect(merged.subscriptions == [a, b], "this device keeps its shows, and the next push repairs the server copy")
        #expect(merged.customPrefs["subs"] != remote.customPrefs["subs"])
    }

    @Test func anEmptyRemoteListThatWasWrittenOnPurposeStillUnfollows() {
        let remote = PodcastSyncState(customPrefs: ["subs": "[]", "subsUpdated": "200"])
        #expect(local().merged(withRemote: remote).subscriptions.isEmpty)
    }
}
