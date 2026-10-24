import DesignSystem
import Downloads
import Foundation
import JellyfinKit
import Observation
import Persistence
import Playback
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
        let library: LibraryStore
        let player: AudioPlayer
        let downloads: DownloadsStore
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
            phase = .signedIn(makeSignedIn(session, token: token))
        } else {
            phase = .signedOut
        }
    }

    public func didSignIn(_ session: ServerSession, token: String) throws {
        try store.save(session, token: token)
        phase = .signedIn(makeSignedIn(session, token: token))
    }

    private func makeSignedIn(_ session: ServerSession, token: String) -> SignedIn {
        // A corrupt or unreadable cache shouldn't block sign-in; fall back to a fresh temp database.
        let database = (try? LibraryDatabase.open(serverID: session.serverID, userID: session.userID))
            ?? (try! LibraryDatabase.temporary())
        let library = LibraryStore(session: session, token: token, auth: auth, database: database)
        let downloads = DownloadsStore(session: session, library: library)
        let player = AudioPlayer(library: library.api)
        player.localFile = { [weak downloads] trackID in downloads?.localFile(trackID: trackID) }
        library.afterSync = { [weak downloads] in await downloads?.syncPlaylists() }
        return SignedIn(session: session, library: library, player: player, downloads: downloads)
    }

    public func signOut() async {
        if let (session, token) = store.load() {
            await auth.signOut(session, token: token)
        }
        if case let .signedIn(signedIn) = phase {
            signedIn.player.stop()
            WidgetBridge.clear()
            // Downloaded music is tied to this account; remove it from the device.
            signedIn.downloads.manager?.deleteEverything()
            // The cached library is private to this account; don't leave it on disk.
            LibraryDatabase.delete(serverID: signedIn.session.serverID, userID: signedIn.session.userID)
        }
        store.clear()
        phase = .signedOut
    }
}

public extension AppModel {
    /// Forwards the app delegate's background-transfer completion handler to the download manager.
    static func handleBackgroundSessionEvents(identifier: String, completion: @escaping () -> Void) {
        nonisolated(unsafe) let completion = completion
        BackgroundSessionEvents.store(identifier) { completion() }
    }
}

/// Preview/test factory that skips the Keychain.
extension AppModel {
    static func preview(signedIn: Bool = true) -> AppModel {
        let model = AppModel(deviceName: "Preview", store: SessionStore(keychain: Keychain(service: "preview"), defaults: UserDefaults(suiteName: "preview")!))
        if signedIn {
            let session = Fixtures.session
            let store = LibraryStore(session: session, token: "", auth: model.auth, database: try! LibraryDatabase.temporary())
            model.phase = .signedIn(.init(session: session, library: store, player: AudioPlayer(library: store.api), downloads: DownloadsStore(session: session, library: store)))
        } else {
            model.phase = .signedOut
        }
        return model
    }
}
