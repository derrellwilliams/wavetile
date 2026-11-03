import Foundation

/// Keeps the token from following a redirect off the Jellyfin server.
///
/// Security: URLSession keeps every header on a redirect, `Authorization` included, so a reverse
/// proxy that answers 302 to another host (or to HTTP) would hand that host the token. Redirects
/// on the same origin keep it; any other drops it.
public final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    public static let shared = RedirectGuard()

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(Self.request(request, redirectedFrom: task.originalRequest?.url))
    }

    /// The redirected request, without the `Authorization` header when it leaves `original`'s origin.
    public static func request(_ request: URLRequest, redirectedFrom original: URL?) -> URLRequest {
        guard let original, let target = request.url, !isSameOrigin(original, target) else { return request }
        var request = request
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        return request
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
