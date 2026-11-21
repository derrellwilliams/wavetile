import Foundation
import Testing
@testable import Features

@MainActor
private final class ConnectivityFixture {
    var answers: [Bool?]
    var waits: [Duration] = []
    var probeCount = 0
    /// Retries wait for a minute instead of running at once (the 1 s confirmation still runs).
    var holdsRetries = false
    let immediateWaits: Int
    let url: URL
    var connectivity: Connectivity!

    init(_ answers: [Bool?], immediateWaits: Int = 1, url: String? = nil) {
        self.answers = answers
        self.immediateWaits = immediateWaits
        self.url = URL(string: url ?? "https://\(UUID().uuidString).invalid")!
        connectivity = Connectivity(
            server: .init(url: self.url, id: "test"),
            monitorsNetwork: false,
            probe: { [weak self] _ in
                guard let self else { return false }
                probeCount += 1
                return self.answers.isEmpty ? false : self.answers.removeFirst()
            },
            wait: { [weak self] delay in
                guard let self else { throw CancellationError() }
                waits.append(delay)
                if holdsRetries, delay != .seconds(1) { try await Task.sleep(for: .seconds(60)) }
                // Stop retries beyond the scripted scenario without waiting on wall-clock time.
                guard waits.count <= immediateWaits else { throw CancellationError() }
            }
        )
    }

    /// A request to the server failed (or, with `true`, got an answer).
    func report(_ reachable: Bool, path: String = "Items") {
        connectivity.report(url.appending(path: path), reachable: reachable)
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
    @Test(arguments: ["http://192.168.1.5:8096", "https://jellyfin.example.com"])
    func startsOnlineWithoutAsking(url: String) {
        let fixture = ConnectivityFixture([], url: url)
        #expect(fixture.connectivity.isOnline)
        #expect(fixture.probeCount == 0)
    }

    @Test func aConfirmedFailureMarksTheServerUnreachableAndRetriesUntilItAnswers() async throws {
        let fixture = ConnectivityFixture([false, false, true], immediateWaits: 2)
        fixture.report(false)
        try await fixture.waitUntil { !fixture.connectivity.serverReachable }
        #expect(fixture.connectivity.hasNetwork)
        #expect(!fixture.connectivity.isOnline)
        try await fixture.waitUntil { fixture.connectivity.isOnline }
        #expect(fixture.probeCount == 3)
        #expect(fixture.waits == [.seconds(1), .seconds(2)])
    }

    @Test func oneMissIsntAnOutage() async throws {
        let fixture = ConnectivityFixture([false, true])
        fixture.report(false)
        try await fixture.waitUntil { fixture.probeCount == 2 }
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.connectivity.isOnline)
        #expect(fixture.waits == [.seconds(1)])
    }

    @Test func anAnswerClearsAnUnreachableServerAndItsPendingRetry() async throws {
        let fixture = ConnectivityFixture([false, false])
        fixture.holdsRetries = true
        fixture.connectivity.pathChanged(online: true, interfaces: ["en0"])
        fixture.report(false)
        // The next answer clears it, and the pending retry is dropped.
        try await fixture.waitUntil { !fixture.connectivity.serverReachable }
        fixture.report(true)
        #expect(fixture.connectivity.isOnline)
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.connectivity.isOnline)
    }

    @Test func requestsToOtherServersDontCount() async throws {
        let fixture = ConnectivityFixture([])
        fixture.connectivity.report(URL(string: "https://elsewhere.example.com/Items")!, reachable: false)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fixture.probeCount == 0)
        #expect(fixture.connectivity.isOnline)
    }

    @Test func retriesBackOffFromTwoSecondsToThirty() async throws {
        let fixture = ConnectivityFixture(Array(repeating: false, count: 20), immediateWaits: 16)
        fixture.report(false)
        try await fixture.waitUntil { fixture.waits.count == 17 }
        #expect(fixture.waits == [.seconds(1), .seconds(2)] + Array(repeating: .seconds(5), count: 12) + Array(repeating: .seconds(30), count: 3))
    }

    @Test func pathUpdatesDontRestartTheBackoff() async throws {
        let fixture = ConnectivityFixture(Array(repeating: false, count: 20), immediateWaits: 15)
        fixture.report(false)
        try await fixture.waitUntil { fixture.waits.count == 16 }
        #expect(fixture.waits.last == .seconds(30))
        fixture.holdsRetries = true
        // A new network looks at once, and a miss there keeps the 30 s step.
        fixture.connectivity.pathChanged(online: true, interfaces: ["en1"])
        try await fixture.waitUntil { fixture.waits.count == 17 }
        #expect(fixture.waits.last == .seconds(30))
    }

    @Test func aConfirmedMissedRecheckMarksTheServerUnreachable() async {
        let fixture = ConnectivityFixture([false, false])
        fixture.holdsRetries = true
        await fixture.connectivity.recheck()
        #expect(!fixture.connectivity.serverReachable)
        #expect(fixture.probeCount == 2)
    }

    @Test func overlappingRechecksShareOneProbe() async {
        let fixture = ConnectivityFixture([true])
        async let first: Void = fixture.connectivity.recheck()
        async let second: Void = fixture.connectivity.recheck()
        _ = await (first, second)
        #expect(fixture.connectivity.isOnline)
        #expect(fixture.probeCount == 1)
    }

    @Test func probesVoidedByNetworkChangesKeepTheLastState() async {
        let fixture = ConnectivityFixture([nil, nil, nil, nil])
        await fixture.connectivity.recheck()
        #expect(fixture.connectivity.isOnline)
        #expect(fixture.probeCount == 4)
        #expect(fixture.waits.isEmpty)
    }

    @Test func losingTheNetworkMakesStreamingUnavailableAndIgnoresFailures() {
        let fixture = ConnectivityFixture([])
        fixture.connectivity.pathChanged(online: false, interfaces: [])
        #expect(!fixture.connectivity.hasNetwork)
        #expect(!fixture.connectivity.isOnline)
        // The offline notice already says it; the server isn't blamed for it.
        fixture.report(false)
        #expect(fixture.connectivity.serverReachable)
        #expect(fixture.probeCount == 0)
    }

    @Test func aNewNetworkLooksAtAnUnreachableServerAtOnce() async throws {
        let fixture = ConnectivityFixture([false, false, true], url: "http://192.168.1.5:8096")
        fixture.holdsRetries = true
        fixture.connectivity.pathChanged(online: true, interfaces: ["pdp_ip0"])
        fixture.report(false)
        try await fixture.waitUntil { !fixture.connectivity.serverReachable }
        // Home Wi-Fi again: no waiting for the next retry.
        fixture.connectivity.pathChanged(online: true, interfaces: ["en0"])
        try await fixture.waitUntil { fixture.connectivity.isOnline }
        #expect(fixture.probeCount == 3)
    }

    @Test func anUnreachableHTTPServerStillProvesItselfAfterASameInterfaceUpdate() async throws {
        let fixture = ConnectivityFixture([false, false], url: "http://192.168.1.5:8096")
        fixture.holdsRetries = true
        var announced: [Bool] = []
        fixture.connectivity.onNetworkChange = { strict in announced.append(strict) }
        fixture.connectivity.pathChanged(online: true, interfaces: ["en0"])
        fixture.report(false)
        try await fixture.waitUntil { !fixture.connectivity.serverReachable }
        // Café Wi-Fi on the same subnet keeps en0: the token must wait for the server's ID again.
        fixture.connectivity.pathChanged(online: true, interfaces: ["en0"])
        try await fixture.waitUntil { announced == [true, false] }
    }

    @Test func aNetworkChangeDoesntProbeAReachableServer() {
        let fixture = ConnectivityFixture([])
        fixture.connectivity.pathChanged(online: true, interfaces: ["pdp_ip0"])
        #expect(fixture.connectivity.isOnline)
        #expect(fixture.probeCount == 0)
    }

    @Test(arguments: [
        ("http://192.168.1.5:8096/Items", true), ("HTTP://192.168.1.5:8096", true),
        ("http://192.168.1.5/Items", false), ("https://192.168.1.5:8096", false), ("http://192.168.1.6:8096", false),
    ])
    func sameOrigin(url: String, matches: Bool) {
        let server = Connectivity.Server(url: URL(string: "http://192.168.1.5:8096")!, id: "x")
        #expect(server.isSameOrigin(URL(string: url)!) == matches)
    }
}
