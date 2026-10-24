import DesignSystem
import Library
import SwiftUI

struct MainTabView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    let app: AppModel
    let signedIn: AppModel.SignedIn
    @State private var home: HomeModel
    @State private var searchText = ""
    // Debug launch argument `-openSettings` starts with the drawer open (screenshots, design review).
    @State private var showSettings = DebugFlags.openSettings
    @State private var showNowPlaying = false
    @State private var connectivity = Connectivity()
    @State private var actions = LibraryActions()
    @State private var homePath: [LibraryRoute] = []
    @State private var widgets: WidgetBridge
    @Namespace private var playerZoom
    @State private var selection: AppTab = DebugFlags.initialTab
    /// Whether each tab's navigation stack is showing its root screen (drives edge-swipe-to-open).
    @State private var atRoot: [AppTab: Bool] = [:]

    enum AppTab: String, Hashable { case home, library, downloaded, search }

    init(app: AppModel, signedIn: AppModel.SignedIn) {
        self.app = app
        self.signedIn = signedIn
        let home = HomeModel(library: signedIn.library.api)
        let widgets = WidgetBridge(player: signedIn.player, library: signedIn.library)
        home.onRecentlyPlayed = { [weak widgets] albums in widgets?.recentsChanged(albums) }
        _home = State(initialValue: home)
        _widgets = State(initialValue: widgets)
    }

    var body: some View {
        SideDrawer(isOpen: $showSettings, edgeSwipeEnabled: atRoot[selection, default: true]) {
            tabs
        } drawer: {
            SettingsDrawer(app: app, session: signedIn.session, isOpen: $showSettings)
        }
        .environment(signedIn.library)
        .environment(signedIn.player)
        .environment(signedIn.downloads)
        .environment(connectivity)
        .environment(actions)
        .libraryActionSheets(actions)
        .task { await signedIn.downloads.observe() }
        // Background library sync: on launch if stale (>1h); pull to refresh in Library forces one.
        .task { await signedIn.library.syncIfNeeded() }
        .enableInjection()
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab(value: .home) {
                HomeView(model: home, userName: signedIn.session.userName, showSettings: $showSettings, path: $homePath)
                    .environment(\.tabRootReporter, reporter(for: .home))
            } label: {
                Label("Home", glyph: .home)
            }
            Tab(value: .library) {
                LibraryView()
                    .environment(\.tabRootReporter, reporter(for: .library))
            } label: {
                Label("Library", glyph: .library)
            }
            Tab(value: .downloaded) {
                DownloadedView()
                    .environment(\.tabRootReporter, reporter(for: .downloaded))
            } label: {
                Label("Downloaded", glyph: .downloads)
            }
            Tab(value: .search, role: .search) {
                SearchView(text: $searchText)
                    .environment(\.tabRootReporter, reporter(for: .search))
            } label: {
                Label("Search", glyph: .search)
            }
        }
        // Required on iOS 27 for the detached search button (searchable lives in SearchView).
        .tabViewSearchActivation(.searchTabSelection)
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: signedIn.player.current?.queueID) { widgets.playerChanged() }
        .onChange(of: signedIn.player.isPlaying) { widgets.playerChanged() }
        .onOpenURL(perform: openLink)
        .onChange(of: signedIn.player.hasQueue) { _, hasQueue in
            if hasQueue, DebugFlags.openNowPlaying { showNowPlaying = true }
        }
        .tabViewBottomAccessory(isEnabled: signedIn.player.hasQueue) {
            miniPlayer
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
                .presentationBackground(theme.palette.background)
                .navigationTransition(.zoom(sourceID: "miniPlayer", in: playerZoom))
        }
    }
}

extension MainTabView {
    /// Widget deep links: `wavetile://album/<id>` pushes the album on Home; `now-playing` opens the player.
    fileprivate func openLink(_ url: URL) {
        guard url.scheme == "wavetile" else { return }
        showSettings = false
        switch url.host() {
        case "now-playing":
            if signedIn.player.hasQueue { showNowPlaying = true }
        case "album":
            let id = url.lastPathComponent
            guard let record = try? signedIn.library.database.album(id: id) else { return }
            selection = .home
            homePath = [.album(AlbumRoute(album: record.summary, sourceID: "link-\(id)"))]
        default:
            break
        }
    }

    @ViewBuilder fileprivate var miniPlayer: some View {
        let player = signedIn.player
        if let track = player.current {
            MiniPlayerBar(
                title: track.title,
                subtitle: track.artist,
                artwork: signedIn.library.artwork(itemID: track.albumID, tag: track.albumImageTag, maxPixelWidth: 144),
                isPlaying: player.isPlaying,
                onPlayPause: { player.togglePlayPause() },
                onNext: { player.next() }
            )
            .contentShape(.rect)
            .onTapGesture { showNowPlaying = true }
            .matchedTransitionSource(id: "miniPlayer", in: playerZoom)
            .accessibilityAction(named: "Open Now Playing") { showNowPlaying = true }
        }
    }

    private func reporter(for tab: AppTab) -> TabRootReporter {
        TabRootReporter { isRoot in atRoot[tab] = isRoot }
    }
}

/// Lets a tab's root screen report whether it's visible, i.e. nothing is pushed on top of it.
struct TabRootReporter {
    var report: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var tabRootReporter = TabRootReporter()
}

extension View {
    /// Apply to the root content *inside* a tab's `NavigationStack`. Pushing a screen makes it
    /// disappear; returning makes it reappear, so the tab's root state stays accurate.
    func reportsTabRoot() -> some View {
        modifier(ReportsTabRoot())
    }
}

private struct ReportsTabRoot: ViewModifier {
    @Environment(\.tabRootReporter) private var reporter

    func body(content: Content) -> some View {
        content
            .onAppear { reporter.report(true) }
            .onDisappear { reporter.report(false) }
    }
}

enum DebugFlags {
    #if DEBUG
    static let openSettings = ProcessInfo.processInfo.arguments.contains("-openSettings")
    static let openFirstAlbum = ProcessInfo.processInfo.arguments.contains("-openFirstAlbum")
    /// With `-openFirstAlbum`, `-albumIndex 2` opens the third album on the first shelf.
    static let albumIndex = UserDefaults.standard.integer(forKey: "albumIndex")
    /// `-autoplay` starts the album opened by `-openFirstAlbum`; `-openNowPlaying` then shows the player.
    static let autoplay = ProcessInfo.processInfo.arguments.contains("-autoplay")
    static let openNowPlaying = ProcessInfo.processInfo.arguments.contains("-openNowPlaying")
    /// `-autodownload` downloads the album opened by `-openFirstAlbum`.
    static let autodownload = ProcessInfo.processInfo.arguments.contains("-autodownload")
    /// `-tab library` starts on that tab.
    static let initialTab: MainTabView.AppTab = UserDefaults.standard.string(forKey: "tab").flatMap(MainTabView.AppTab.init) ?? .home
    #else
    static let openSettings = false
    static let openFirstAlbum = false
    static let initialTab: MainTabView.AppTab = .home
    static let albumIndex = 0
    static let autoplay = false
    static let openNowPlaying = false
    static let autodownload = false
    #endif
}
