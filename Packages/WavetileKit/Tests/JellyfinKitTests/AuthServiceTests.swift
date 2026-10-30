import Foundation
import Testing
@testable import JellyfinKit

/// Serves canned responses keyed by URL path; records requests for assertions.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.lock.withLock {
            Self.requests.append(request)
            return Self.routes[request.url?.path() ?? ""] ?? (404, Data())
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset(_ routes: [String: (Int, String)]) {
        lock.withLock {
            self.routes = routes.mapValues { ($0.0, Data($0.1.utf8)) }
            requests = []
        }
    }
}

@Suite(.serialized)
struct AuthServiceTests {
    let service: AuthService = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let identity = ClientIdentity(clientName: "Wavetile", version: "1.0", deviceName: "Test", deviceID: "device-1")
        return AuthService(identity: identity, sessionConfiguration: config)
    }()

    let systemInfo = #"{"Id":"srv1","ServerName":"Home","Version":"10.11.0","StartupWizardCompleted":true}"#
    let authResult = #"{"AccessToken":"tok123","ServerId":"srv1","User":{"Id":"u1","Name":"derrell"}}"#

    @Test func validateReadsServerAndQuickConnect() async throws {
        MockURLProtocol.reset([
            "/System/Info/Public": (200, systemInfo),
            "/QuickConnect/Enabled": (200, "true"),
        ])
        let info = try await service.validate(try ServerAddress("https://music.example.com"))
        #expect(info.id == "srv1")
        #expect(info.name == "Home")
        #expect(info.isQuickConnectEnabled)
    }

    @Test func validateRejectsNonJellyfin() async throws {
        MockURLProtocol.reset(["/System/Info/Public": (200, #"{"hello":"world"}"#)])
        await #expect(throws: AuthService.AuthError.notAJellyfinServer) {
            try await service.validate(try ServerAddress("https://example.com"))
        }
    }

    @Test func validateRefusesRemoteHTTP() async throws {
        MockURLProtocol.reset(["/System/Info/Public": (200, systemInfo)])
        await #expect(throws: AuthService.AuthError.insecureTransport) {
            try await service.validate(try ServerAddress("http://music.example.com:8096"))
        }
        #expect(MockURLProtocol.requests.isEmpty)
    }

    @Test func quickConnectYieldsCodeThenSession() async throws {
        MockURLProtocol.reset([
            "/System/Info/Public": (200, systemInfo),
            "/QuickConnect/Enabled": (200, "true"),
            "/QuickConnect/Initiate": (200, #"{"Code":"123456","Secret":"s3cret","Authenticated":false}"#),
            "/QuickConnect/Connect": (200, #"{"Code":"123456","Secret":"s3cret","Authenticated":true}"#),
            "/Users/AuthenticateWithQuickConnect": (200, authResult),
        ])
        let info = try await service.validate(try ServerAddress("https://music.example.com"))

        var events: [AuthService.QuickConnectEvent] = []
        for try await event in service.quickConnect(info, pollSeconds: 1) { events.append(event) }

        #expect(events.first == .code("123456"))
        guard case let .signedIn(session, token) = events.last else {
            Issue.record("expected signedIn, got \(events)")
            return
        }
        #expect(token == "tok123")
        #expect(session.userID == "u1")
        #expect(session.userName == "derrell")

        let authHeader = MockURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") ?? ""
        #expect(authHeader.contains("Client=Wavetile"))
        #expect(authHeader.contains("DeviceId=device-1"))
    }

    @Test func quickConnectFailsWhenDisabled() async throws {
        MockURLProtocol.reset([
            "/System/Info/Public": (200, systemInfo),
            "/QuickConnect/Enabled": (200, "false"),
        ])
        let info = try await service.validate(try ServerAddress("https://music.example.com"))
        await #expect(throws: AuthService.AuthError.quickConnectDisabled) {
            for try await _ in service.quickConnect(info) {}
        }
    }
}
