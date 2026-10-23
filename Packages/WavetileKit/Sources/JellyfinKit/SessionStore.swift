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

/// Persists the active session. Metadata goes to UserDefaults, the access token to the Keychain.
public struct SessionStore: Sendable {
    private let keychain: Keychain
    private let defaultsKey = "activeSession"
    // UserDefaults is documented thread-safe but not marked Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(keychain: Keychain = Keychain(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
    }

    public func load() -> (session: ServerSession, token: String)? {
        guard let data = defaults.data(forKey: defaultsKey),
              let session = try? JSONDecoder().decode(ServerSession.self, from: data),
              let token = try? keychain.string(for: session.tokenAccount)
        else { return nil }
        return (session, token)
    }

    public func save(_ session: ServerSession, token: String) throws {
        try keychain.set(token, for: session.tokenAccount)
        defaults.set(try JSONEncoder().encode(session), forKey: defaultsKey)
    }

    public func clear() {
        if let data = defaults.data(forKey: defaultsKey),
           let session = try? JSONDecoder().decode(ServerSession.self, from: data) {
            try? keychain.remove(session.tokenAccount)
        }
        defaults.removeObject(forKey: defaultsKey)
    }
}
