import Foundation

/// Keeps the token from following a redirect off the Jellyfin server.
///
/// Security: URLSession keeps every header on a redirect, `Authorization` included, so a reverse
/// proxy that answers 302 to another host (or to HTTP) would hand that host the token. Redirects
/// on the same origin keep it; cross-origin reads drop it and writes are refused.
///
/// Limit: this only runs for default and ephemeral sessions. A background `URLSession` always
/// follows redirects without asking its delegate, so background downloads can't be stopped
/// mid-redirect; they use `leftOrigin` afterwards to halt and contain the exposure.
public final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    public static let shared = RedirectGuard()

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(Self.request(request, redirectedFrom: task.originalRequest?.url))
    }

    /// Safe redirected reads lose Authorization off-origin; off-origin writes return nil.
    public static func request(_ request: URLRequest, redirectedFrom original: URL?) -> URLRequest? {
        guard let original, let target = request.url else { return nil }
        guard !isSameOrigin(original, target) else { return request }
        // 307/308 can preserve a login password or Quick Connect secret in the body.
        // Stripping Authorization alone does not protect those credentials.
        guard ["GET", "HEAD"].contains(request.httpMethod ?? "GET"),
              request.httpBody == nil, request.httpBodyStream == nil else { return nil }
        var request = request
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        return request
    }

    /// True when a finished or failed task ended up on a different origin than the one requested,
    /// which is how a background session (that can't veto redirects) reveals a redirect off the server.
    public static func leftOrigin(requested original: URL?, ended final: URL?) -> Bool {
        guard let original, let final else { return false }
        return !isSameOrigin(original, final)
    }

    static func isSameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased()
            && a.host()?.lowercased() == b.host()?.lowercased()
            && effectivePort(a) == effectivePort(b)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : url.scheme?.lowercased() == "http" ? 80 : nil)
    }
}
