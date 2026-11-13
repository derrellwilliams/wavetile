import Foundation
import Testing
@testable import Features

@MainActor
private final class ConnectivityFixture {
    var answers: [Bool?]
    var waits: [Duration] = []
    var probeCount = 0
    var holdsConfirmation = false
    var onlineDuringWait: [Bool] = []
    let immediateWaits: Int
    var connectivity: Connectivity!

    init(_ answers: [Bool?], immediateWaits: Int = 1) {
        self.answers = answers
        self.immediateWaits = immediateWaits
        connectivity = Connectivity(
            server: .init(url: URL(string: "https://\(UUID().uuidString).invalid")!, id: "test"),
            monitorsNetwork: false,
            probe: { [weak self] _ in
                guard let self else { return false }
                probeCount += 1
                return self.answers.isEmpty ? false : self.answers.removeFirst()
            },
            wait: { [weak self] delay in
                guard let self else { throw CancellationError() }
                waits.append(delay)
                onlineDuringWait.append(connectivity.isOnline)
                if holdsConfirmation { try await Task.sleep(for: .seconds(60)) }
                // Stop retries beyond the scripted scenario without waiting on wall-clock time.
                guard waits.count <= immediateWaits else { throw CancellationError() }
            }
        )
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition())
    }
}

@Suite @MainActor
struct ConnectivityTests {
    @Test func aTransientStreamProbeFailureKeepsAlbumsAvailable() async {
        let fixture = ConnectivityFixture([false, true])
        await fixture.connectivity.recheck()
        #expect(fixture.connectivity.isOnline)
        #expect(fixture.probeCount == 2)
        #expect(fixture.waits == [.seconds(1)])
        #expect(fixture.onlineDuringWait == [true])
    }

    @Test func twoFailedProbesMarkTheServerUnreachable() async {
        let fixture = ConnectivityFixture([false, false])
        await fixture.connectivity.recheck()
        #expect(fixture.connectivity.hasNetwork)
        #expect(!fixture.connectivity.serverReachable)
        #expect(!fixture.connectivity.isOnline)
    }

    @Test func recoveryRestoresAlbumsWithoutAnotherNetworkEvent() async throws {
        let fixture = ConnectivityFixture([false, false, true], immediateWaits: 2)
        await fixture.connectivity.recheck()
        try await fixture.waitUntil { fixture.connectivity.isOnline && fixture.probeCount == 3 }
        #expect(fixture.waits == [.seconds(1), .seconds(2)])
        #expect(fixture.onlineDuringWait == [true, false])
    }

    @Test func recoveryBackoffNeverExceedsFiveSeconds() async throws {
        let fixture = ConnectivityFixture(Array(repeating: false, count: 7) + [true], immediateWaits: 7)
        await fixture.connectivity.recheck()
        try await fixture.waitUntil { fixture.connectivity.isOnline && fixture.probeCount == 8 }
        #expect(fixture.waits == [.seconds(1), .seconds(2), .seconds(4), .seconds(5), .seconds(5), .seconds(5), .seconds(5)])
    }

    @Test func voidedProbesKeepTheLastGoodStateAndRetry() async throws {
        let fixture = ConnectivityFixture([nil, nil, nil, nil, false, true], immediateWaits: 2)
        await fixture.connectivity.recheck()
        try await fixture.waitUntil { fixture.probeCount == 6 }
        #expect(fixture.connectivity.isOnline)
        #expect(fixture.onlineDuringWait == [true, true])
    }

    @Test func aRealNetworkChangeAlsoConfirmsATransientMiss() async {
        let fixture = ConnectivityFixture([false, true])
        fixture.connectivity.pathChanged(online: true, interfaces: ["en0"])
        await fixture.connectivity.recheck()
        #expect(fixture.connectivity.isOnline)
        #expect(fixture.probeCount == 2)
        #expect(fixture.onlineDuringWait == [true])
    }

    @Test func overlappingStreamErrorsShareACheckAndNetworkLossCancelsItsConfirmation() async throws {
        let fixture = ConnectivityFixture([false, true])
        fixture.holdsConfirmation = true
        let first = Task { await fixture.connectivity.recheck() }
        try await fixture.waitUntil { fixture.waits.count == 1 }
        var secondStarted = false
        let second = Task {
            secondStarted = true
            await fixture.connectivity.recheck()
        }
        try await fixture.waitUntil { secondStarted }
        #expect(fixture.connectivity.isOnline)
        #expect(fixture.probeCount == 1)
        fixture.connectivity.pathChanged(online: false, interfaces: [])
        await first.value
        await second.value
        #expect(!fixture.connectivity.isOnline)
        #expect(fixture.probeCount == 1)
    }

    @Test func losingTheNetworkImmediatelyMakesStreamingUnavailable() async {
        let fixture = ConnectivityFixture([true])
        fixture.connectivity.pathChanged(online: false, interfaces: [])
        #expect(!fixture.connectivity.isOnline)
        await fixture.connectivity.recheck()
        #expect(fixture.probeCount == 0)
    }
}
