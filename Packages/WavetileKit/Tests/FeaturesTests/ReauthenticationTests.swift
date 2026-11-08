import Foundation
import Testing
import os
@testable import JellyfinKit
@testable import Features

nonisolated private final class UnauthorizedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

nonisolated private final class MemoryCredentials: SessionCredentials, Sendable {
    private let values = OSAllocatedUnfairLock(initialState: [String: String]())
    func string(for account: String) throws -> String? { values.withLock { $0[account] } }
    func set(_ value: String, for account: String) throws { values.withLock { $0[account] = value } }
    func remove(_ account: String) throws { _ = values.withLock { $0.removeValue(forKey: account) } }
}

nonisolated private final class HeldSyncProtocol: URLProtocol, @unchecked Sendable {
    static let started = OSAllocatedUnfairLock(initialState: false)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.started.withLock { $0 = true } }
    override func stopLoading() {}
}

@Suite(.serialized) @MainActor
struct ReauthenticationTests {
    @Test func signOutCancelsAnInFlightSyncAndClosesItsPool() async throws {
        HeldSyncProtocol.started.withLock { $0 = false }
        let id = UUID().uuidString
        let defaults = UserDefaults(suiteName: id)!
        let store = SessionStore(credentials: MemoryCredentials(), defaults: defaults)
        defer { store.clear(); defaults.removePersistentDomain(forName: id) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeldSyncProtocol.self]
        let auth = AuthService(identity: .init(clientName: "Test", version: "1", deviceName: "Test", deviceID: id), sessionConfiguration: config)
        let app = AppModel(deviceName: "Test", store: store, auth: auth)
        let session = ServerSession(serverURL: URL(string: "https://sync.invalid")!, serverID: id, serverName: "Test", userID: id, userName: "Test")
        try app.didSignIn(session, token: "synthetic")
        guard case let .signedIn(account) = app.phase else { Issue.record("Not signed in"); return }
        let sync = Task { await account.library.syncNow() }
        for _ in 0..<100 where !HeldSyncProtocol.started.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(HeldSyncProtocol.started.withLock { $0 })
        #expect(await app.signOut())
        await sync.value
        #expect(throws: (any Error).self) { try account.library.database.pool.read { _ in () } }
        #expect(throws: (any Error).self) { try account.podcasts.database.pool.read { _ in () } }
        try app.didSignIn(session, token: "new-synthetic")
        guard case let .signedIn(reopened) = app.phase else { Issue.record("Could not sign in again"); return }
        #expect(try reopened.library.database.syncState() == nil)
        await app.signOut()
    }

    @Test func recoveryPreservesAccountObjectsAndDownloadedFiles() async throws {
        let id = UUID().uuidString
        let defaults = UserDefaults(suiteName: id)!
        let store = SessionStore(credentials: MemoryCredentials(), defaults: defaults)
        defer {
            store.clear()
            defaults.removePersistentDomain(forName: id)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UnauthorizedProtocol.self]
        let auth = AuthService(identity: .init(clientName: "Test", version: "1", deviceName: "Test", deviceID: id), sessionConfiguration: config)
        let app = AppModel(deviceName: "Test", store: store, auth: auth)
        let session = ServerSession(serverURL: URL(string: "https://reauth.invalid")!, serverID: id, serverName: "Test", userID: id, userName: "Test")
        try app.didSignIn(session, token: "synthetic-expired")
        guard case let .signedIn(before) = app.phase else { Issue.record("Not signed in"); return }
        let file = try #require(before.downloads.manager).directory.appending(path: "synthetic.mp3")
        try Data("offline fixture".utf8).write(to: file)
        await before.library.api.checkAuthentication()
        for _ in 0..<100 where !app.needsReauthentication { await Task.yield() }
        #expect(app.needsReauthentication)
        var wrongAccount = session
        wrongAccount.userID = "different"
        #expect(throws: AppModel.ReauthenticationError.self) {
            try app.didSignIn(wrongAccount, token: "synthetic-wrong")
        }
        #expect(store.load()?.token == "synthetic-expired")
        app.showsReauthentication = true
        try app.didSignIn(session, token: "synthetic-renewed")
        guard case let .signedIn(after) = app.phase else { Issue.record("Lost session"); return }
        #expect(before.library === after.library)
        #expect(before.player === after.player)
        #expect(before.downloads === after.downloads)
        #expect(before.podcasts === after.podcasts)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(store.load()?.token == "synthetic-renewed")
        #expect(!app.needsReauthentication)
        #expect(!app.showsReauthentication)
        await app.signOut()
        #expect(throws: (any Error).self) { try before.library.database.pool.read { _ in () } }
    }
}
