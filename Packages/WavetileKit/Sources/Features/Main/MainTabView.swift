import DesignSystem
import GRDB
import Library
import Podcasts
import SwiftUI

struct MainTabView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    let app: AppModel
    let signedIn: AppModel.SignedIn
    @State private var home: HomeModel
    @State private var searchText = ""
    @State private var showNowPlaying = false
    @State private var connectivity = Connectivity.shared
    @State private var actions = LibraryActions()
    @State private var homePath = NavigationPath()
    @State private var widgets: WidgetBridge
    @Namespace private var playerZoom
    @State private var selection: AppTab = DebugFlags.initialTab
    // Debug launch argument `-openSettings` starts with the drawer open (screenshots, design review).
    @State private var showSettings = DebugFlags.openSettings
    /// Whether each tab's navigation stack is showing its root screen (drives edge-swipe-to-open).
    @State private var atRoot: [AppTab: Bool] = [:]
    /// Search's All | Music | Podcasts filter (Podcasts' "+" opens Search on the Podcasts side).
    @State private var searchScope: MediaKind = .all
    @State private var showOPMLImporter = false
    @State private var opmlMessage: String?

    enum AppTab: String, Hashable { case home, music, podcasts, downloaded, search }

    init(app: AppModel, signedIn: AppModel.SignedIn) {
        self.app = app
        self.signedIn = signedIn
        let home = HomeModel(library: signedIn.library.api, database: signedIn.library.database, userID: signedIn.session.userID)
        let widgets = WidgetBridge(player: signedIn.player, library: signedIn.library)
        home.onRecentlyPlayed = { [weak widgets] albums in widgets?.recentsChanged(albums) }
        _home = State(initialValue: home)
        _widgets = State(initialValue: widgets)
    }

    var body: some View {
        SideDrawer(isOpen: $showSettings, edgeSwipeEnabled: atRoot[selection, default: true]) {
            tabs
                .environment(\.openProfile) { showSettings = true }
                .environment(\.openNowPlaying) { showNowPlaying = true }
                .environment(\.openPodcastSearch, openPodcastSearch)
        } drawer: {
            SettingsDrawer(app: app, session: signedIn.session, isOpen: $showSettings)
        }
        // Sheets must sit inside the environment below, or their content can't find the library
        // store and SwiftUI traps (TestFlight 1.0.0 (2): Add to Collection crashed).
        .libraryActionSheets(actions)
        .environment(signedIn.library)
        .environment(\.isAudioPlaying, signedIn.player.isPlaying)
        .environment(signedIn.player)
        .environment(signedIn.downloads)
        .environment(signedIn.podcasts)
        .environment(connectivity)
        .environment(actions)
        .task { await signedIn.downloads.observe() }
        .task { await signedIn.podcasts.run() }
        .task { await applyPodcastDebugFlags() }
        // Background library sync: on launch if stale (>1h); pull to refresh in Library forces one.
        .task { await signedIn.library.syncIfNeeded() }
        .enableInjection()
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab(value: .home) {
                HomeView(model: home, path: $homePath, userName: signedIn.session.userName, upNext: signedIn.podcasts.launchUpNext)
                    .environment(\.tabRootReporter, reporter(for: .home))
            } label: {
                tabLabel("Home", glyph: .home)
            }
            Tab(value: .music) {
                LibraryView()
                    .environment(\.tabRootReporter, reporter(for: .music))
            } label: {
                tabLabel("Music", glyph: .library)
            }
            // Opt-in from the profile drawer; music-only users never see it.
            if signedIn.podcasts.isEnabled {
                Tab(value: .podcasts) {
                    PodcastsView()
                        .environment(\.tabRootReporter, reporter(for: .podcasts))
                } label: {
                    tabLabel("Podcasts", glyph: .podcasts)
                }
            }
            Tab(value: .downloaded) {
                DownloadedView()
                    .environment(\.tabRootReporter, reporter(for: .downloaded))
            } label: {
                tabLabel("Downloads", glyph: .downloads)
            }
            Tab(value: .search, role: .search) {
                SearchView(text: $searchText, scope: $searchScope)
                    .environment(\.tabRootReporter, reporter(for: .search))
            } label: {
                tabLabel("Search", glyph: .search)
            }
        }
        // Required on iOS 27 for the detached search button (searchable lives in SearchView).
        .tabViewSearchActivation(.searchTabSelection)
        .tabBarMinimizeBehavior(.never)
        .onChange(of: signedIn.player.current?.queueID) {
            widgets.playerChanged()
            home.albumStartedPlaying(signedIn.player.current?.albumID)
            signedIn.podcasts.playerChanged()
        }
        .onChange(of: signedIn.podcasts.isEnabled) { _, enabled in
            guard !enabled else { return }
            searchScope = .all
            if selection == .podcasts { selection = .home }
        }
        .sheet(isPresented: introBinding) {
            PodcastsIntroSheet(
                onFindShows: { openPodcastSearch() },
                onImport: { showOPMLImporter = true }
            )
            .environment(signedIn.podcasts)
        }
        .opmlImporter(isPresented: $showOPMLImporter, message: $opmlMessage)
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
            homePath = NavigationPath([LibraryRoute.album(AlbumRoute(album: record.summary, sourceID: "link-\(id)"))])
        default:
            break
        }
    }

    /// The first time podcasts are turned on (once the drawer has closed), explain them.
    private var introBinding: Binding<Bool> {
        Binding(
            get: { signedIn.podcasts.isEnabled && !signedIn.podcasts.hasSeenIntro && !showSettings },
            set: { if !$0 { signedIn.podcasts.hasSeenIntro = true } }
        )
    }

    /// `-enablePodcasts`, `-followFeed <url>` and `-playLatestEpisode` (debug builds only).
    private func applyPodcastDebugFlags() async {
        let podcasts = signedIn.podcasts
        if DebugFlags.enablePodcasts {
            podcasts.hasSeenIntro = true
            podcasts.isEnabled = true
        }
        if let feed = DebugFlags.followFeed, let show = try? await podcasts.follow(feedURL: feed) {
            if DebugFlags.playLatestEpisode, let latest = try? await podcasts.database.pool.read({ db in
                try EpisodeRecord.filter(Column("showID") == show.id).order(Column("publishedAt").desc).fetchOne(db)
            }), let item = try? podcasts.database.episodeNow(id: latest.id) {
                podcasts.play(item)
                if DebugFlags.openNowPlaying { showNowPlaying = true }
            }
        }
    }

    fileprivate func openPodcastSearch() {
        showSettings = false
        searchScope = .podcasts
        selection = .search
    }

    @ViewBuilder fileprivate var miniPlayer: some View {
        let player = signedIn.player
        if let track = player.current {
            MiniPlayerBar(
                title: track.title,
                // Episodes show their show; songs their artist.
                subtitle: track.isEpisode ? track.albumTitle : track.artist,
                artwork: signedIn.library.artwork(for: track, maxPixelWidth: 144),
                isPlaying: player.isPlaying,
                nextGlyph: track.isEpisode ? .skipForward : .next,
                nextTitle: track.isEpisode ? "Skip Forward \(Int(player.skipForwardInterval)) Seconds" : "Next",
                onPlayPause: { player.togglePlayPause() },
                onNext: { track.isEpisode ? player.skip(by: player.skipForwardInterval) : player.next() }
            )
            .contentShape(.rect)
            .onTapGesture { showNowPlaying = true }
            .matchedTransitionSource(id: "miniPlayer", in: playerZoom)
            .accessibilityAction(named: "Open Now Playing") { showNowPlaying = true }
        }
    }

    private func tabLabel(_ title: String, glyph: Glyph) -> some View {
        // The glass tab bar keeps titles system-colored for legibility; only the icon can be tinted.
        Label {
            Text(title)
        } icon: {
            glyph.image(color: theme.palette.accent)
        }
    }

    private func reporter(for tab: AppTab) -> TabRootReporter {
        TabRootReporter { isRoot in atRoot[tab] = isRoot }
    }
}

/// Profile button at top left. A plain bar item, so it gets the same system glass and icon
/// size as the buttons on pushed screens.
struct ProfileButton: View {
    @Environment(\.openProfile) private var openProfile

    var body: some View {
        Button("Profile and Settings", glyph: .user, action: openProfile)
    }
}

/// Lets a tab's root screen report whether it's visible, i.e. nothing is pushed on top of it.
struct TabRootReporter {
    var report: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var tabRootReporter = TabRootReporter()
    /// Opens the profile and settings drawer.
    @Entry var openProfile: () -> Void = {}
    /// Presents the Now Playing sheet.
    @Entry var openNowPlaying: () -> Void = {}
}

extension View {
    /// Chrome for a tab's root screen, applied to the content *inside* its `NavigationStack`:
    /// the profile button at top left (opens the drawer), and root reporting so the drawer's
    /// edge swipe only works at the root, never fighting the system back gesture.
    /// `trailing` adds screen buttons (plain `Label`s) next to AirPlay in the top-right capsule.
    /// `centersTitle` keeps the title centered (Home's wordmark); other tabs keep theirs leading.
    func tabRootChrome(centersTitle: Bool = false) -> some View {
        modifier(TabRootChrome(centersTitle: centersTitle) { EmptyView() })
    }

    func tabRootChrome<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(TabRootChrome(trailing: trailing()))
    }
}

private struct TabRootChrome<Trailing: View>: ViewModifier {
    @Environment(\.tabRootReporter) private var reporter
    var centersTitle = false
    let trailing: Trailing

    init(trailing: Trailing) { self.trailing = trailing }
    init(centersTitle: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.centersTitle = centersTitle
        self.trailing = trailing()
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProfileButton()
                }
                // AirPlay and the screen's buttons share one capsule of the bar's glass,
                // like the trailing buttons on pushed screens.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    AirPlayButton(iconSize: 24, tapSize: nil)
                    trailing
                }
            }
            // Keeps the scrolled-up title at the leading edge on every tab, not centered on some.
            .toolbarRole(centersTitle ? .automatic : .browser)
            // Pushing a screen makes the root disappear; returning makes it reappear.
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
    /// `-tab music` starts on that tab.
    static let initialTab: MainTabView.AppTab = UserDefaults.standard.string(forKey: "tab").flatMap(MainTabView.AppTab.init) ?? .home
    static let enablePodcasts = ProcessInfo.processInfo.arguments.contains("-enablePodcasts")
    /// `-followFeed https://…` follows that feed at launch; `-playLatestEpisode` then plays its newest episode.
    static let followFeed = UserDefaults.standard.string(forKey: "followFeed").flatMap(URL.init(string:))
    static let playLatestEpisode = ProcessInfo.processInfo.arguments.contains("-playLatestEpisode")
    /// `-openLatestEpisode` opens the newest followed episode's page on the Podcasts tab.
    static let openLatestEpisode = ProcessInfo.processInfo.arguments.contains("-openLatestEpisode")
    /// `-freshHome` shows Home as a new listener sees it: no play history or podcast Up Next.
    static let freshHome = ProcessInfo.processInfo.arguments.contains("-freshHome")
    /// `-openArtist` (with `-openFirstAlbum`) goes on to that album's artist page.
    static let openArtist = ProcessInfo.processInfo.arguments.contains("-openArtist")
    #else
    static let freshHome = false
    static let openSettings = false
    static let openFirstAlbum = false
    static let initialTab: MainTabView.AppTab = .home
    static let albumIndex = 0
    static let autoplay = false
    static let openNowPlaying = false
    static let autodownload = false
    static let enablePodcasts = false
    static let followFeed: URL? = nil
    static let playLatestEpisode = false
    static let openLatestEpisode = false
    static let openArtist = false
    #endif
}
