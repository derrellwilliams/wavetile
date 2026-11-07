import Foundation
import Testing
@testable import JellyfinKit

struct SessionStoreTests {
    private enum Failure: Error { case unavailable }

    private struct Credentials: SessionCredentials {
        var read: @Sendable (String) throws -> String? = { _ in "test-token" }
        var write: @Sendable (String, String) throws -> Void = { _, _ in }
        var delete: @Sendable (String) throws -> Void = { _ in }
        func string(for account: String) throws -> String? { try read(account) }
        func set(_ value: String, for account: String) throws { try write(value, account) }
        func remove(_ account: String) throws { try delete(account) }
    }

    private let session = ServerSession(
        serverURL: URL(string: "https://example.com")!, serverID: "server",
        serverName: "Test", userID: "user", userName: "Listener"
    )

    private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let name = "SessionStoreTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try test(defaults)
    }

    @Test func failedDeletionCannotRestoreSession() throws {
        try withDefaults { defaults in
            let credentials = Credentials(delete: { _ in throw Failure.unavailable })
            let store = SessionStore(credentials: credentials, defaults: defaults)
            try store.save(session, token: "test-token")
            #expect(store.load()?.session == session)
            store.clear()
            #expect(defaults.data(forKey: "activeSession") == nil)
            // Simulate a new store after relaunch with the undeleted token still readable.
            let relaunched = SessionStore(credentials: credentials, defaults: defaults)
            #expect(relaunched.load() == nil)
        }
    }

    @Test func failedWriteDoesNotPublishSession() throws {
        try withDefaults { defaults in
            let store = SessionStore(credentials: Credentials(write: { _, _ in throw Failure.unavailable }), defaults: defaults)
            #expect(throws: Failure.self) { try store.save(session, token: "test-token") }
            #expect(defaults.data(forKey: "activeSession") == nil)
            #expect(store.load() == nil)
        }
    }

    @Test func transientReadFailureDoesNotEraseSession() throws {
        try withDefaults { defaults in
            let healthy = SessionStore(credentials: Credentials(), defaults: defaults)
            try healthy.save(session, token: "test-token")
            let unavailable = SessionStore(credentials: Credentials(read: { _ in throw Failure.unavailable }), defaults: defaults)
            #expect(unavailable.load() == nil)
            #expect(defaults.data(forKey: "activeSession") != nil)
            #expect(healthy.load()?.session == session)
        }
    }

    @Test func missingTokenCannotRestoreSession() throws {
        try withDefaults { defaults in
            let store = SessionStore(credentials: Credentials(read: { _ in nil }), defaults: defaults)
            try store.save(session, token: "test-token")
            #expect(store.load() == nil)
        }
    }

    @Test func failedReplacementPreservesPreviousMetadata() throws {
        try withDefaults { defaults in
            try SessionStore(credentials: Credentials(), defaults: defaults).save(session, token: "test-token")
            let before = defaults.data(forKey: "activeSession")
            var replacement = session
            replacement.userID = "other-user"
            let store = SessionStore(credentials: Credentials(write: { _, _ in throw Failure.unavailable }), defaults: defaults)
            #expect(throws: Failure.self) { try store.save(replacement, token: "other-token") }
            #expect(defaults.data(forKey: "activeSession") == before)
        }
    }
}
