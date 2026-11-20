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

    init(_ answers: [Bool?], immediateWaits: Int = 1, url: String? = nil) {
        self.answers = answers
        self.immediateWaits = immediateWaits
        connectivity = Connectivity(
            server: .init(url: URL(string: url ?? "https://\(UUID().uuidString).invalid")!, id: "test"),
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
        fixture.connectivity.pathChanged(online: true, interfaces: ["en0"], localRoute: true)
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
        fixture.connectivity.pathChanged(online: false, interfaces: [], localRoute: false)
        await first.value
        await second.value
        #expect(!fixture.connectivity.isOnline)
        #expect(fixture.probeCount == 1)
    }

    @Test func losingTheNetworkImmediatelyMakesStreamingUnavailable() async {
        let fixture = ConnectivityFixture([true])
        fixture.connectivity.pathChanged(online: false, interfaces: [], localRoute: false)
        #expect(!fixture.connectivity.isOnline)
        await fixture.connectivity.recheck()
        #expect(fixture.probeCount == 0)
    }

    @Test func anHTTPServerShowsOnlineWhileItsFirstCheckRuns() async {
        let fixture = ConnectivityFixture([true], url: "http://192.168.1.5:8096")
        #expect(fixture.connectivity.isOnline)
        await fixture.connectivity.recheck()
        #expect(fixture.connectivity.isOnline)
    }

    @Test func anHTTPServerMissingItsFirstCheckGoesOfflineWithoutConfirmation() async throws {
        let fixture = ConnectivityFixture([false], url: "http://192.168.1.5:8096")
        fixture.holdsConfirmation = true
        await fixture.connectivity.recheck()
        #expect(!fixture.connectivity.serverReachable)
        #expect(fixture.probeCount == 1)
        // The only wait is the retry after the miss (offline), not a confirmation (still online).
        try await fixture.waitUntil { fixture.waits.count == 1 }
        #expect(fixture.onlineDuringWait == [false])
    }

    @Test func anHTTPServerWhoseFirstCheckNeverAnswersGoesOffline() async throws {
        let fixture = ConnectivityFixture([nil, nil, nil, nil], url: "http://192.168.1.5:8096")
        fixture.holdsConfirmation = true
        await fixture.connectivity.recheck()
        #expect(fixture.probeCount == 4)
        #expect(!fixture.connectivity.serverReachable)
    }

    @Test func turningWiFiOffMarksALocalServerUnreachableAtOnce() async throws {
        let fixture = ConnectivityFixture([true], url: "http://192.168.1.5:8096")
        fixture.connectivity.pathChanged(online: true, interfaces: ["en0", "pdp_ip0"], localRoute: true)
        await fixture.connectivity.recheck()
        #expect(fixture.connectivity.isOnline)
        fixture.holdsConfirmation = true
        fixture.connectivity.pathChanged(online: true, interfaces: ["pdp_ip0"], localRoute: false)
        try await fixture.waitUntil { !fixture.connectivity.serverReachable }
        #expect(fixture.connectivity.hasNetwork)
        #expect(!fixture.connectivity.isOnline)
        // The miss lands without the 1 s confirmation, and the next look waits the short backoff.
        try await fixture.waitUntil { fixture.waits.count == 1 }
        #expect(fixture.waits == [.seconds(1)])
    }

    @Test func aVPNThatReachesTheLocalServerKeepsItOnline() async throws {
        let fixture = ConnectivityFixture([true, true], url: "http://192.168.1.5:8096")
        fixture.connectivity.pathChanged(online: true, interfaces: ["pdp_ip0"], localRoute: false)
        await fixture.connectivity.recheck()
        #expect(fixture.connectivity.isOnline)
        // Chatter on the same path no longer marks it offline before probing.
        fixture.connectivity.pathChanged(online: true, interfaces: ["pdp_ip0"], localRoute: false)
        try await fixture.waitUntil { fixture.probeCount == 2 }
        #expect(fixture.connectivity.isOnline)
    }

    @Test func noRouteHomeBacksOffToThirtySeconds() async throws {
        let fixture = ConnectivityFixture(Array(repeating: false, count: 6), immediateWaits: 5, url: "http://10.0.0.2")
        fixture.connectivity.pathChanged(online: true, interfaces: ["pdp_ip0"], localRoute: false)
        try await fixture.waitUntil { fixture.waits.count == 6 }
        #expect(fixture.waits == [.seconds(1), .seconds(2), .seconds(4), .seconds(30), .seconds(30), .seconds(30)])
    }

    @Test func losingTheNetworkForgetsAnUnconfirmedMiss() async throws {
        let fixture = ConnectivityFixture([false, false, true], immediateWaits: 2)
        fixture.holdsConfirmation = true
        let first = Task { await fixture.connectivity.recheck() }
        try await fixture.waitUntil { fixture.waits.count == 1 }
        fixture.connectivity.pathChanged(online: false, interfaces: [], localRoute: false)
        await first.value
        fixture.holdsConfirmation = false
        fixture.connectivity.pathChanged(online: true, interfaces: ["en0"], localRoute: true)
        // Back online, one miss gets its confirmation again instead of dimming at once.
        try await fixture.waitUntil { fixture.probeCount == 3 }
        #expect(fixture.connectivity.isOnline)
    }

    @Test func aRestartedCheckStillConfirmsAMiss() async throws {
        let fixture = ConnectivityFixture([false, false])
        fixture.holdsConfirmation = true
        let first = Task { await fixture.connectivity.recheck() }
        try await fixture.waitUntil { fixture.waits.count == 1 }
        // A path update lands during the 1 s confirmation and restarts the check.
        fixture.connectivity.pathChanged(online: true, interfaces: ["pdp_ip0"], localRoute: false)
        try await fixture.waitUntil { !fixture.connectivity.serverReachable }
        #expect(fixture.probeCount == 2)
        await first.value
    }

    @Test(arguments: [
        ("http://192.168.1.5:8096", true), ("http://10.0.0.2", true), ("http://172.20.1.1", true),
        ("http://nas.local:8096", true), ("http://[fd00::1]:8096", true), ("http://169.254.3.3", true),
        ("http://172.32.0.1", false), ("http://100.101.102.103", false), ("https://jellyfin.example.com", false),
        ("https://192.168.1.5.example.com", false), ("http://[fd::1]:8096", false), ("http://010.0.0.1", false),
        ("http://home.tail1234.ts.net", false), ("http://[fd7a:115c:a1e0::1]:8096", false),
    ])
    func localOnlyAddresses(url: String, localOnly: Bool) {
        #expect(Connectivity.Server(url: URL(string: url)!, id: "x").isLocalOnly == localOnly)
    }
}
