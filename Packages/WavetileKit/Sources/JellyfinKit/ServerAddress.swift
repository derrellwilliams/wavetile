import Foundation

/// A user-entered server address, normalized and classified for transport security.
public struct ServerAddress: Hashable, Sendable {
    public let url: URL

    public enum InputError: Error, Equatable {
        case empty
        case invalid
    }

    /// Accepts loose input like `music.example.com`, `192.168.1.5:8096`, or a full URL.
    /// Bare hosts default to HTTPS; the user must type `http://` explicitly to opt out.
    public init(_ input: String) throws(InputError) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .empty }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }

        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              // A name and password in the address would be saved and shown in plain text.
              components.user == nil, components.password == nil,
              let url = components.url
        else { throw .invalid }

        self.url = url
    }

    /// Addresses to try, in order, for loosely typed input.
    ///
    /// An explicit scheme is respected as-is. Without one, HTTPS is tried first, except on
    /// Jellyfin's default HTTP port 8096. HTTP is only offered for local-network hosts:
    /// ATS blocks it over the internet, where it would expose the token anyway.
    public static func candidates(for input: String) throws(InputError) -> [ServerAddress] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let secure = try ServerAddress(trimmed)
        if trimmed.contains("://") { return [secure] }
        let plain = try ServerAddress("http://" + trimmed)
        guard plain.isLocalNetwork else { return [secure] }
        return secure.url.port == 8096 ? [plain, secure] : [secure, plain]
    }

    public var isSecure: Bool { url.scheme?.lowercased() == "https" }

    /// True for hosts that never leave the local network (RFC 1918, link-local, loopback, mDNS),
    /// or that are reached over Tailscale, which encrypts the traffic itself (WireGuard): MagicDNS
    /// `*.ts.net` names and fd7a:115c:a1e0::/48 (covered by fd). Tailscale's 100.64.0.0/10 IPv4
    /// addresses aren't included: carriers use the same range (CGNAT), where HTTP isn't encrypted.
    public var isLocalNetwork: Bool {
        guard let host = url.host()?.lowercased().trimmingCharacters(in: ["[", "]"]) else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" { return true }
        if host.hasSuffix(".ts.net") { return true }
        if host.contains(":") {
            // IPv6 link-local (fe80::/10) and unique-local (fc00::/7). The first group has to be
            // written in full: `fd::1` is 00fd::1, a public address.
            guard let first = host.split(separator: ":", omittingEmptySubsequences: false).first, first.count == 4 else { return false }
            return ["fc", "fd", "fe8", "fe9", "fea", "feb"].contains { first.hasPrefix($0) }
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        // Plain decimal only: `010.1.1.1` can be read as octal (8.1.1.1), a public address.
        let octets = parts.compactMap { part in UInt8(part).flatMap { String($0) == part ? $0 : nil } }
        guard parts.count == 4, octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (169, 254), (192, 168): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    /// Plain HTTP to a non-local host sends the access token in cleartext.
    public var transportWarning: TransportWarning? {
        if isSecure { return nil }
        return isLocalNetwork ? .insecureLocal : .insecureRemote
    }

    public enum TransportWarning: Sendable {
        /// HTTP on the LAN or Tailscale: allowed by ATS (local networking, plus a ts.net exception).
        case insecureLocal
        /// HTTP over the internet: blocked by ATS. Use HTTPS (e.g. a Cloudflare Tunnel).
        case insecureRemote
    }
}
