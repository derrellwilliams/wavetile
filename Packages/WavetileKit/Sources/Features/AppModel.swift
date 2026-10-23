import DesignSystem
import Foundation
import JellyfinKit
import Observation
import PreviewSupport

/// Root app state: who is signed in, and the selected theme.
@Observable
public final class AppModel {
    public enum Phase {
        case launching
        case signedOut
        case signedIn(SignedIn)
    }

    public struct SignedIn {
        public let session: ServerSession
        public let library: LibraryClient
    }

    public private(set) var phase: Phase = .launching
    public let auth: AuthService
    private let store: SessionStore
    // Stored on the model, not in @AppStorage, so non-view code can read it later (widgets, Now Playing).
    public var theme: Theme {
        didSet { UserDefaults.standard.set(theme.id, forKey: "themeID") }
    }

    public init(deviceName: String, store: SessionStore = SessionStore()) {
        self.auth = AuthService(identity: .load(deviceName: deviceName))
        self.store = store
        let savedTheme = UserDefaults.standard.string(forKey: "themeID")
        self.theme = Theme.all.first { $0.id == savedTheme } ?? .wavetile
    }

    /// Restores the saved session from the Keychain. Synchronous so the first frame is already correct.
    public func restore() {
        guard case .launching = phase else { return }
        if let (session, token) = store.load() {
            phase = .signedIn(.init(session: session, library: LibraryClient(session: session, token: token, auth: auth)))
        } else {
            phase = .signedOut
        }
    }

    public func didSignIn(_ session: ServerSession, token: String) throws {
        try store.save(session, token: token)
        phase = .signedIn(.init(session: session, library: LibraryClient(session: session, token: token, auth: auth)))
    }

    public func signOut() async {
        if let (session, token) = store.load() {
            await auth.signOut(session, token: token)
        }
        store.clear()
        phase = .signedOut
    }
}

/// Preview/test factory that skips the Keychain.
extension AppModel {
    static func preview(signedIn: Bool = true) -> AppModel {
        let model = AppModel(deviceName: "Preview", store: SessionStore(keychain: Keychain(service: "preview"), defaults: UserDefaults(suiteName: "preview")!))
        if signedIn {
            let session = Fixtures.session
            model.phase = .signedIn(.init(session: session, library: LibraryClient(session: session, token: "", auth: model.auth)))
        } else {
            model.phase = .signedOut
        }
        return model
    }
}
