import BackgroundTasks
import DesignSystem
import Downloads
import Foundation
import JellyfinKit
import Observation
import Persistence
import Playback
import Podcasts
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
        let podcasts: PodcastsStore
        let authorization: SessionAuthorization?
        let authorizationID: UUID
    }

    public private(set) var phase: Phase = .launching
    var needsReauthentication = false
    var showsReauthentication = false
    private var authorization: SessionAuthorization?
    private(set) var authorizationID = UUID()
    public let auth: AuthService
    private var signingOut = false
    private let store: SessionStore
    // Stored on the model, not in @AppStorage, so non-view code can read it later (widgets, Now Playing).
    public var theme: Theme {
        didSet { UserDefaults.standard.set(theme.id, forKey: "themeID") }
    }

    /// Called when the names Siri should know change: after a library sync and on sign in or out.
    /// Set by the app target, which owns the App Shortcuts provider.
    @ObservationIgnored public var onLibraryVocabularyChanged: (() -> Void)?

    /// The app's model, for entry points that don't go through SwiftUI (CarPlay, Siri).
    public private(set) static weak var current: AppModel?

    public init(deviceName: String, store: SessionStore = SessionStore(), auth: AuthService? = nil) {
        self.auth = auth ?? AuthService(identity: .load(deviceName: deviceName))
        self.store = store
        let savedTheme = UserDefaults.standard.string(forKey: "themeID")
        self.theme = Theme.all.first { $0.id == savedTheme } ?? .dark
        Self.current = self
        _ = Connectivity.shared
        // Once per launch, here rather than in a view's init (which re-runs on every app body
        // update), and before CarPlay, which can launch the app with no phone window at all.
        BrandFont.register()
        ImageCaching.configure()
        BrandFont.applyNavigationBarAppearance()
    }

    /// Restores the saved session from the Keychain. Synchronous so the first frame is already correct.
    public func restore() {
        guard case .launching = phase else { return }
        let saved = store.load()
        if let (session, token) = saved, Self.isTransportAllowed(session.serverURL),
           let signedIn = try? makeSignedIn(session, token: token) {
            activate(signedIn)
        } else {
            // A session that can't be used again shouldn't leave its token in the Keychain.
            if let saved, !Self.isTransportAllowed(saved.session.serverURL) { store.clear() }
            // No saved session, or no usable library storage (signing in again reports why).
            // Widgets from an earlier session must not keep showing that account's music.
            WidgetBridge.clear()
            phase = .signedOut
        }
    }

    /// Sessions saved before remote HTTP was refused at sign-in must not keep sending the token in cleartext.
    private static func isTransportAllowed(_ url: URL) -> Bool {
        (try? ServerAddress(url.absoluteString))?.transportWarning != .insecureRemote
    }

    enum ReauthenticationError: Error { case wrongAccount }

    public func didSignIn(_ session: ServerSession, token: String) throws {
        if case let .signedIn(current) = phase {
            guard current.session.serverID == session.serverID,
                  current.session.userID == session.userID,
                  current.session.serverURL == session.serverURL else {
                throw ReauthenticationError.wrongAccount
            }
            try store.save(session, token: token)
            authorization?.replaceToken(token)
            needsReauthentication = false
            showsReauthentication = false
            return
        }
        let signedIn = try makeSignedIn(session, token: token)
        try store.save(session, token: token)
        activate(signedIn)
    }

    private func activate(_ signedIn: SignedIn) {
        authorization = signedIn.authorization
        authorizationID = signedIn.authorizationID
        phase = .signedIn(signedIn)
        onLibraryVocabularyChanged?()
    }

    /// Throws `StorageUnavailable` only when no database can be created at all (e.g. the disk is full).
    private func makeSignedIn(_ session: ServerSession, token: String) throws -> SignedIn {
        // First, so nothing built below can send the token to an HTTP address that hasn't proved itself.
        ServerIdentity.shared.register(session.serverURL, serverID: session.serverID)
        // A corrupt or unreadable cache shouldn't block sign-in; fall back to a fresh temp database.
        let database: LibraryDatabase
        do {
            database = try LibraryDatabase.open(serverID: session.serverID, userID: session.userID)
        } catch {
            Log.storageFallback("library", error)
            do { database = try LibraryDatabase.temporary() } catch { throw StorageUnavailable() }
        }
        let authorizationID = UUID()
        let authorization = SessionAuthorization(token: token) { [weak self] in
            Task { @MainActor in
                guard let self, self.authorizationID == authorizationID,
                      self.authorization?.isRejected == true,
                      case .signedIn = self.phase else { return }
                self.needsReauthentication = true
            }
        }
        let accountAuth = auth.withAuthorization(authorization)
        let library = LibraryStore(session: session, token: token, auth: accountAuth, database: database)
        let downloads = DownloadsStore(session: session, library: library)
        let player = AudioPlayer(library: library.api)
        let podcastDatabase: PodcastDatabase
        do {
            podcastDatabase = try PodcastDatabase.open(serverID: session.serverID, userID: session.userID)
        } catch {
            Log.storageFallback("podcast", error)
            guard let temporary = try? PodcastDatabase.temporary() else { throw StorageUnavailable() }
            podcastDatabase = temporary
        }
        let podcasts = PodcastsStore(session: session, library: library.api, player: player, database: podcastDatabase)
        player.localFile = { [weak downloads, weak podcasts] id in
            downloads?.localFile(trackID: id) ?? podcasts?.localFile(episodeID: id)
        }
        // Episodes stream from their publishers, so they only need a network; music needs the server.
        player.canStream = { track in
            track.isEpisode ? Connectivity.shared.hasNetwork : Connectivity.shared.isOnline
        }
        player.isOnDevice = { [weak downloads, weak podcasts] track in
            track.isEpisode
                ? podcasts?.localFile(episodeID: track.trackID) != nil
                : downloads?.isDownloaded(track.trackID) == true
        }
        player.onConnectionError = { track in
            if !track.isEpisode {
                await Connectivity.shared.recheck()
                if Connectivity.shared.isOnline { await library.api.checkAuthentication() }
            }
        }
        Connectivity.shared.server = .init(url: session.serverURL, id: session.serverID)
        Connectivity.shared.onNetworkChange = { [weak downloads, weak player] in
            await downloads?.networkChanged()
            player?.networkChanged()
        }
        Connectivity.shared.onForeground = { [weak player] in player?.enteredForeground() }
        player.resumePosition = { [weak podcasts] track in podcasts?.resumePosition(for: track) }
        player.onEpisodeProgress = { [weak podcasts] track, position, duration in
            podcasts?.episodeProgress(track, position: position, duration: duration)
        }
        library.afterSync = { [weak downloads, weak self] in
            await downloads?.syncPlaylists()
            self?.onLibraryVocabularyChanged?()
        }
        player.onUnreportedPlay = { [weak library] trackID, date in
            Task { try? await library?.database.queuePlay(trackID: trackID, at: date) }
        }
        return SignedIn(session: session, library: library, player: player, downloads: downloads, podcasts: podcasts, authorization: authorization, authorizationID: authorizationID)
    }

    @discardableResult
    public func signOut() async -> Bool {
        guard !signingOut else { return false }
        signingOut = true
        defer { signingOut = false }
        if case let .signedIn(signedIn) = phase {
            signedIn.player.stop()
            guard await signedIn.podcasts.shutdown(), await signedIn.library.shutdown() else { return false }
            WidgetBridge.clear()
            await DownloadsStore.endAllLiveActivities()
            Connectivity.shared.server = nil
            // Downloaded music is tied to this account; remove it from the device.
            signedIn.downloads.manager?.deleteEverything()
            // Podcast progress and downloads belong to this account too.
            signedIn.podcasts.downloads?.deleteEverything()
            PodcastDatabase.delete(serverID: signedIn.session.serverID, userID: signedIn.session.userID)
            // The cached library is private to this account; don't leave it on disk.
            LibraryDatabase.delete(serverID: signedIn.session.serverID, userID: signedIn.session.userID)
            // A stand-in database (the real one wouldn't open) lives in the temporary folder.
            signedIn.library.database.deleteStandInFiles()
            signedIn.podcasts.database.deleteStandInFiles()
            RecentSearches.clearStored()
            ImageCaching.removeAll()
        }
        if let (session, token) = store.load() {
            Task.detached { [auth] in await auth.signOut(session, token: token) }
        }
        authorizationID = UUID()
        authorization = nil
        needsReauthentication = false
        showsReauthentication = false
        store.clear()
        phase = .signedOut
        onLibraryVocabularyChanged?()
        return true
    }
}

public extension AppModel {
    /// Forwards the app delegate's background-transfer completion handler to the download manager.
    static func handleBackgroundSessionEvents(identifier: String, completion: @escaping () -> Void) {
        nonisolated(unsafe) let completion = completion
        BackgroundSessionEvents.store(identifier) { completion() }
    }
}

// MARK: - Background podcast refresh

public extension AppModel {
    nonisolated static let podcastRefreshTaskID = "com.derrellwilliams.wavetile.podcast-refresh"

    /// Registers the background refresh handler. Call once at launch, before launching finishes.
    func registerBackgroundTasks() {
        Self.registerRefresh { [weak self] in
            guard let self, case let .signedIn(signedIn) = self.phase else { return true }
            let ok = await signedIn.podcasts.backgroundRefresh()
            self.scheduleBackgroundRefresh()
            return ok
        }
    }

    /// Asks iOS to wake the app in about an hour to check followed shows for new episodes.
    func scheduleBackgroundRefresh() {
        guard case let .signedIn(signedIn) = phase, signedIn.podcasts.isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.podcastRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The launch handler runs on a background queue, so it's built outside the main actor
    /// (a main-actor closure there traps at runtime).
    private nonisolated static func registerRefresh(_ refresh: @escaping @Sendable @MainActor () async -> Bool) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: podcastRefreshTaskID, using: nil) { task in
            nonisolated(unsafe) let task = task
            let work = Task { @MainActor in
                let ok = await refresh()
                task.setTaskCompleted(success: ok && !Task.isCancelled)
            }
            task.expirationHandler = { work.cancel() }
        }
    }
}

/// The device couldn't create the library database (usually no free storage).
struct StorageUnavailable: Error {}

#if DEBUG
/// Preview/test factory that skips the Keychain. Debug only, so the sample data stays out of Release.
extension AppModel {
    static func preview(signedIn: Bool = true) -> AppModel {
        let model = AppModel(deviceName: "Preview", store: SessionStore(keychain: Keychain(service: "preview"), defaults: UserDefaults(suiteName: "preview")!))
        if signedIn {
            let session = Fixtures.session
            let store = LibraryStore(session: session, token: "", auth: model.auth, database: try! LibraryDatabase.temporary())
            let player = AudioPlayer(library: store.api)
            let podcasts = PodcastsStore(session: session, library: store.api, player: player, database: try! PodcastDatabase.temporary())
            model.phase = .signedIn(.init(session: session, library: store, player: player, downloads: DownloadsStore(session: session, library: store), podcasts: podcasts, authorization: nil, authorizationID: UUID()))
        } else {
            model.phase = .signedOut
        }
        return model
    }
}
#endif
