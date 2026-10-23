import Foundation
import JellyfinKit
import Observation

@Observable
final class SignInModel {
    enum Route: Hashable {
        case quickConnect
        case password
    }

    var addressText = ""
    var path: [Route] = []
    private(set) var server: AuthService.ServerInfo?
    private(set) var isWorking = false
    private(set) var quickConnectCode: String?
    var errorMessage: String?

    private let app: AppModel
    private var quickConnectTask: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
    }

    var transportWarning: ServerAddress.TransportWarning? {
        (try? ServerAddress(addressText))?.transportWarning
    }

    func connect() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            var lastError: (any Error)?
            for address in try ServerAddress.candidates(for: addressText) {
                do {
                    let info = try await app.auth.validate(address)
                    server = info
                    // Show what actually connected so the HTTP warning reflects reality.
                    addressText = address.url.absoluteString
                    path = [info.isQuickConnectEnabled ? .quickConnect : .password]
                    return
                } catch let error as URLError {
                    lastError = error  // Wrong scheme/port shows up as a transport error; try the next one.
                }
            }
            if let lastError { throw lastError }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func startQuickConnect() {
        guard let server else { return }
        quickConnectTask?.cancel()
        quickConnectCode = nil
        errorMessage = nil
        quickConnectTask = Task {
            do {
                for try await event in app.auth.quickConnect(server) {
                    switch event {
                    case let .code(code):
                        quickConnectCode = code
                    case let .signedIn(session, token):
                        try app.didSignIn(session, token: token)
                    }
                }
            } catch is CancellationError {
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    func stopQuickConnect() {
        quickConnectTask?.cancel()
        quickConnectTask = nil
    }

    func signIn(username: String, password: String) async {
        guard let server else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let (session, token) = try await app.auth.signIn(server, username: username, password: password)
            try app.didSignIn(session, token: token)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    static func message(for error: any Error) -> String {
        switch error {
        case ServerAddress.InputError.empty: "Enter your server address."
        case ServerAddress.InputError.invalid: "That doesn't look like a valid address."
        case AuthService.AuthError.notAJellyfinServer: "No Jellyfin server found at that address."
        case AuthService.AuthError.setupIncomplete: "Finish setting up this server in a browser first."
        case AuthService.AuthError.quickConnectDisabled: "Quick Connect is turned off on this server."
        case let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection:
            "This server uses plain HTTP over the internet. Use an HTTPS address."
        case let error as URLError: error.localizedDescription
        default: "Sign in failed. Check your details and try again."
        }
    }
}
