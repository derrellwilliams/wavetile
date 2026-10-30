import Foundation
import Testing
@testable import Playback

struct PlaybackQueueTests {
    func tracks(_ count: Int) -> [QueuedTrack] {
        (0 ..< count).map { QueuedTrack(trackID: "t\($0)", title: "T\($0)", artist: "A", albumTitle: "Al", albumID: "al", duration: .seconds(60)) }
    }

    @Test func startsAtIndexAndListsUpNext() {
        let queue = PlaybackQueue(tracks: tracks(4), startAt: 1)
        #expect(queue.current?.trackID == "t1")
        #expect(queue.upNext.map(\.trackID) == ["t2", "t3"])
    }

    @Test func automaticAdvanceStopsAtEndWithoutRepeat() {
        var queue = PlaybackQueue(tracks: tracks(2), startAt: 1)
        #expect(queue.automaticNext == nil)
        let r1 = queue.advanceAutomatically()
        #expect(!r1)
    }

    @Test func repeatAllWrapsAndRepeatOneStays() {
        var queue = PlaybackQueue(tracks: tracks(2), startAt: 1)
        queue.repeatMode = .all
        #expect(queue.automaticNext?.trackID == "t0")
        let r2 = queue.advanceAutomatically()
        #expect(r2)
        #expect(queue.current?.trackID == "t0")

        queue.repeatMode = .one
        #expect(queue.automaticNext?.trackID == "t0")
        let r3 = queue.advanceAutomatically()
        #expect(r3)
        #expect(queue.current?.trackID == "t0")
    }

    @Test func skipForwardIgnoresRepeatOne() {
        var queue = PlaybackQueue(tracks: tracks(3))
        queue.repeatMode = .one
        let r4 = queue.skipForward()
        #expect(r4)
        #expect(queue.current?.trackID == "t1")
    }

    @Test func playNextInsertsAfterCurrentAndAppendGoesLast() {
        var queue = PlaybackQueue(tracks: tracks(3))
        let extra = QueuedTrack(trackID: "x", title: "X", artist: "A", albumTitle: "Al", albumID: nil, duration: nil)
        let last = QueuedTrack(trackID: "y", title: "Y", artist: "A", albumTitle: "Al", albumID: nil, duration: nil)
        queue.playNext([extra])
        queue.append([last])
        #expect(queue.upNext.map(\.trackID) == ["x", "t1", "t2", "y"])
    }

    @Test func shuffleKeepsCurrentAndUnshuffleRestoresOrder() {
        var queue = PlaybackQueue(tracks: tracks(20), startAt: 5)
        queue.setShuffle(true)
        #expect(queue.current?.trackID == "t5")
        #expect(queue.index == 0)
        #expect(Set(queue.items.map(\.trackID)).count == 20)

        queue.setShuffle(false)
        #expect(queue.items.map(\.trackID) == (0 ..< 20).map { "t\($0)" })
        #expect(queue.current?.trackID == "t5")
    }

    @Test func removeAndMoveUpNext() {
        var queue = PlaybackQueue(tracks: tracks(4))
        queue.remove(queue.items[2].queueID)
        #expect(queue.upNext.map(\.trackID) == ["t1", "t3"])
        queue.moveUpNext(fromOffsets: [1], toOffset: 0)
        #expect(queue.upNext.map(\.trackID) == ["t3", "t1"])
        // The current track can't be removed.
        queue.remove(queue.current!.queueID)
        #expect(queue.current?.trackID == "t0")
    }

    @Test func duplicatesAreDistinctEntries() {
        var queue = PlaybackQueue(tracks: tracks(1))
        queue.append([queue.current!.requeued()])
        #expect(queue.items.count == 2)
        #expect(queue.items[0].queueID != queue.items[1].queueID)
    }
}

struct PlayCountRuleTests {
    @Test func halfASongOrFourMinutesCounts() {
        #expect(AudioPlayer.countsAsPlay(position: 100, duration: 180))
        #expect(!AudioPlayer.countsAsPlay(position: 80, duration: 180))
        #expect(AudioPlayer.countsAsPlay(position: 240, duration: 1200))
        #expect(!AudioPlayer.countsAsPlay(position: 0, duration: 0))
    }
}
