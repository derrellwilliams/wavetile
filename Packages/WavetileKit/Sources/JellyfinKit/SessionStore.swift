import Foundation

/// A signed-in user on a specific server. Contains no secrets; the token lives in the Keychain.
public struct ServerSession: Codable, Hashable, Sendable {
    public var serverURL: URL
    public var serverID: String
    public var serverName: String
    public var userID: String
    public var userName: String

    public init(serverURL: URL, serverID: String, serverName: String, userID: String, userName: String) {
        self.serverURL = serverURL
        self.serverID = serverID
        self.serverName = serverName
        self.userID = userID
        self.userName = userName
    }

    var tokenAccount: String { "token.\(serverID).\(userID)" }
}

/// Internal seam for exercising OS Keychain failures without accessing real credentials.
protocol SessionCredentials: Sendable {
    func string(for account: String) throws -> String?
    func set(_ value: String, for account: String) throws
    func remove(_ account: String) throws
}

extension Keychain: SessionCredentials {}

/// Persists the active session. Metadata goes to UserDefaults, the access token to the Keychain.
public struct SessionStore: Sendable {
    private let keychain: any SessionCredentials
    private let defaultsKey = "activeSession"
    private let cleanupKey = "pendingSessionTokenCleanup"
    // UserDefaults is documented thread-safe but not marked Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(keychain: Keychain = Keychain(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
    }

    init(credentials: any SessionCredentials, defaults: UserDefaults) {
        self.keychain = credentials
        self.defaults = defaults
    }

    public func load() -> (session: ServerSession, token: String)? {
        // A pending deletion also marks a signed-out session if clear was interrupted.
        if let session = savedSession, pendingCleanup.contains(session.tokenAccount) {
            defaults.removeObject(forKey: defaultsKey)
        }
        retryCleanup()
        guard let session = savedSession,
              let token = try? keychain.string(for: session.tokenAccount)
        else { return nil }
        return (session, token)
    }

    public func save(_ session: ServerSession, token: String) throws {
        let data = try JSONEncoder().encode(session)
        try keychain.set(token, for: session.tokenAccount)
        // A successful new sign-in replaces the old secret; never delete its new token.
        pendingCleanup = pendingCleanup.filter { $0 != session.tokenAccount }
        defaults.set(data, forKey: defaultsKey)
        retryCleanup()
    }

    public func clear() {
        if let session = savedSession {
            pendingCleanup = Array(Set(pendingCleanup + [session.tokenAccount]))
        }
        defaults.removeObject(forKey: defaultsKey)
        retryCleanup()
    }

    private var savedSession: ServerSession? {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(ServerSession.self, from: $0) }
    }

    /// Only account identifiers are retained; tokens never leave the Keychain.
    private var pendingCleanup: [String] {
        get { defaults.stringArray(forKey: cleanupKey) ?? [] }
        nonmutating set {
            if newValue.isEmpty { defaults.removeObject(forKey: cleanupKey) }
            else { defaults.set(newValue, forKey: cleanupKey) }
        }
    }

    /// Retry on session load, save and clear; persistent OS failures remain queued.
    private func retryCleanup() {
        pendingCleanup = pendingCleanup.filter { account in
            do {
                try keychain.remove(account)
                return false
            } catch {
                return true
            }
        }
    }
}
