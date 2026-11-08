import Foundation
import Get
import os

/// Whether the machine answering at the saved address is the signed-in Jellyfin server.
///
/// Security: a plain-HTTP address (`http://192.168.1.5:8096`) names a different machine on every
/// network, and anything at that address on café Wi-Fi with the same subnet would get the token
/// in cleartext. So the token waits until the address answers Jellyfin's public info endpoint
/// (sent without the token) with the saved server's ID, once per network. HTTPS skips the wait:
/// the certificate already proves the host.
public final class ServerIdentity: Sendable {
    public static let shared = ServerIdentity()

    private struct Server {
        let url: URL
        let id: String
    }

    private struct State {
        /// Servers signed in on this launch, by origin. Kept after sign-out, so revoking the token waits too.
        var servers: [String: Server] = [:]
        /// HTTP origins that answered with their ID on the current network.
        var verified: Set<String> = []
        var pending: [String: Task<Bool, Never>] = [:]
        /// Bumped on every network change, so a check from the old network can't vouch for the new one.
        var generation = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Short timeout and no waiting for a network: the answer is needed now, not eventually.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// On sign-in and session restore.
    public func register(_ url: URL, serverID: String) {
        guard let origin = Self.origin(url) else { return }
        state.withLock { $0.servers[origin] = Server(url: url, id: serverID) }
    }

    /// The device changed networks: every HTTP server has to prove itself again before it gets the token.
    public func networkChanged() {
        state.withLock { state in
            state.generation += 1
            state.verified = []
            state.pending = [:]
        }
    }

    /// Whether the token may go to `url` right now, for callers that can't wait (stream requests).
    public func allowsToken(to url: URL) -> Bool {
        guard Self.isCleartext(url), let origin = Self.origin(url) else { return true }
        return state.withLock { $0.servers[origin] == nil || $0.verified.contains(origin) }
    }

    /// Whether the token may go to `url`, checking the server's ID first if this network hasn't yet.
    /// An HTTP address that isn't a signed-in server (signing in) passes: there's no ID to check against.
    public func confirmToken(to url: URL) async -> Bool {
        guard !allowsToken(to: url) else { return true }
        return await check(url)
    }

    /// Asks the server at `url` for its ID now (no token), and for HTTP remembers the answer for this network.
    public func check(_ url: URL) async -> Bool {
        guard let origin = Self.origin(url) else { return false }
        let task: Task<Bool, Never>? = state.withLock { state in
            guard let server = state.servers[origin] else { return nil }
            if let pending = state.pending[origin] { return pending }
            let generation = state.generation
            let task = Task { [self] in
                let matches = await Self.identify(server, session: session)
                return self.state.withLock { state in
                    // A check that started on another network says nothing about this one.
                    guard state.generation == generation else { return false }
                    state.pending[origin] = nil
                    if matches { state.verified.insert(origin) } else { state.verified.remove(origin) }
                    return matches
                }
            }
            state.pending[origin] = task
            return task
        }
        return await task?.value ?? false
    }

    @concurrent private static func identify(_ server: Server, session: URLSession) async -> Bool {
        struct PublicInfo: Decodable {
            let Id: String?
        }
        let url = server.url.appending(path: "System/Info/Public")
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let id = (try? JSONDecoder().decode(PublicInfo.self, from: data))?.Id
        else { return false }
        // A session saved without an ID can't be matched; any Jellyfin answer has to do.
        guard !server.id.isEmpty else { return true }
        let normalized = { (id: String) in id.lowercased().replacingOccurrences(of: "-", with: "") }
        return normalized(id) == normalized(server.id)
    }

    private static func isCleartext(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "http"
    }

    private static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased() else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }
}

/// Holds API requests that carry the token until `ServerIdentity` vouches for the server.
struct ServerIdentityCheck: APIClientDelegate {
    var authorization: SessionAuthorization? = nil

    func client(_ client: APIClient, validateResponse response: HTTPURLResponse, data: Data, task: URLSessionTask) throws {
        if response.statusCode == 401, let authorization,
           let original = task.originalRequest?.url, let final = response.url,
           RedirectGuard.isSameOrigin(original, final),
           let header = task.originalRequest?.value(forHTTPHeaderField: "Authorization"),
           let token = Self.token(in: header) {
            authorization.reject(token: token)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.unacceptableStatusCode(response.statusCode)
        }
    }

    private static func token(in header: String) -> String? {
        header.replacingOccurrences(of: "MediaBrowser ", with: "").components(separatedBy: ", ").first(where: { $0.hasPrefix("Token=") })
            .map { String($0.dropFirst(6)) }
    }

    func client(_ client: APIClient, willSendRequest request: inout URLRequest) async throws {
        if let authorization, let header = request.value(forHTTPHeaderField: "Authorization") {
            let fields = header.replacingOccurrences(of: "MediaBrowser ", with: "").components(separatedBy: ", ").filter { !$0.hasPrefix("Token=") }
            request.setValue("MediaBrowser " + (fields + ["Token=\(authorization.token)"]).joined(separator: ", "), forHTTPHeaderField: "Authorization")
        }
        guard let url = request.url,
              request.value(forHTTPHeaderField: "Authorization")?.contains("Token=") == true
        else { return }
        guard await ServerIdentity.shared.confirmToken(to: url) else { throw URLError(.cannotConnectToHost) }
    }
}
