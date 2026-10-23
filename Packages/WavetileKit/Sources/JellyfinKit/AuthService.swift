import Foundation
@_exported import JellyfinAPI

/// Server validation and sign-in (Quick Connect or username/password).
public struct AuthService: Sendable {
    public let identity: ClientIdentity
    private let sessionConfiguration: URLSessionConfiguration

    public init(identity: ClientIdentity, sessionConfiguration: URLSessionConfiguration = .default) {
        self.identity = identity
        self.sessionConfiguration = sessionConfiguration
    }

    public struct ServerInfo: Sendable, Equatable {
        public let address: ServerAddress
        public let id: String
        public let name: String
        public let version: String?
        public let isQuickConnectEnabled: Bool
    }

    public enum AuthError: Error, Equatable {
        case notAJellyfinServer
        case setupIncomplete
        case quickConnectDisabled
        case missingUser
    }

    public enum QuickConnectEvent: Sendable, Equatable {
        case code(String)
        case signedIn(ServerSession, token: String)
    }

    public func makeClient(for url: URL, token: String? = nil) -> JellyfinAPI.JellyfinClient {
        JellyfinAPI.JellyfinClient(
            configuration: .init(
                url: url,
                accessToken: token,
                client: identity.clientName,
                deviceName: identity.deviceName,
                deviceID: identity.deviceID,
                version: identity.version
            ),
            sessionConfiguration: sessionConfiguration
        )
    }

    /// Confirms the address is a usable Jellyfin server and whether Quick Connect is on.
    public func validate(_ address: ServerAddress) async throws -> ServerInfo {
        let client = makeClient(for: address.url)
        let info: PublicSystemInfo
        do {
            info = try await client.send(Paths.getPublicSystemInfo).value
        } catch is DecodingError {
            throw AuthError.notAJellyfinServer
        }
        guard let id = info.id else { throw AuthError.notAJellyfinServer }
        guard info.isStartupWizardCompleted != false else { throw AuthError.setupIncomplete }

        // Endpoint returns a bare JSON boolean; treat any failure as "disabled".
        let enabledData = try? await client.send(Paths.getQuickConnectEnabled).value
        let quickConnect = enabledData.flatMap { try? JSONDecoder().decode(Bool.self, from: $0) } ?? false

        return ServerInfo(
            address: address,
            id: id,
            name: info.serverName ?? address.url.host() ?? "Jellyfin",
            version: info.version,
            isQuickConnectEnabled: quickConnect
        )
    }

    /// Emits the code to show the user, then the session once they approve it in another Jellyfin client.
    /// Cancel the consuming task to stop polling.
    public func quickConnect(_ server: ServerInfo, pollSeconds: Int = 3) -> AsyncThrowingStream<QuickConnectEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard server.isQuickConnectEnabled else { throw AuthError.quickConnectDisabled }
                    let client = makeClient(for: server.address.url)
                    for try await event in client.quickConnect.connect(poll: pollSeconds) {
                        switch event {
                        case let .polling(code):
                            continuation.yield(.code(code))
                        case let .authenticated(secret):
                            let result = try await client.signIn(quickConnectSecret: secret)
                            let (session, token) = try makeSession(server, result)
                            continuation.yield(.signedIn(session, token: token))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func signIn(_ server: ServerInfo, username: String, password: String) async throws -> (ServerSession, token: String) {
        let client = makeClient(for: server.address.url)
        let result = try await client.signIn(username: username, password: password)
        return try makeSession(server, result)
    }

    /// Revokes the token server-side. Local state should be cleared regardless of the outcome.
    public func signOut(_ session: ServerSession, token: String) async {
        try? await makeClient(for: session.serverURL, token: token).signOut()
    }

    private func makeSession(_ server: ServerInfo, _ result: AuthenticationResult) throws -> (ServerSession, token: String) {
        guard let token = result.accessToken else { throw JellyfinAPI.JellyfinClient.ClientError.noAccessToken }
        guard let user = result.user, let userID = user.id else { throw AuthError.missingUser }
        let session = ServerSession(
            serverURL: server.address.url,
            serverID: result.serverID ?? server.id,
            serverName: server.name,
            userID: userID,
            userName: user.name ?? "User"
        )
        return (session, token)
    }
}
