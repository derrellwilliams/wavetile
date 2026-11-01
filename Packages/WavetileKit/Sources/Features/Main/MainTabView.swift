import DesignSystem
import GRDB
import Library
import Podcasts
import SwiftUI
import UIKit

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
        // Something that isn't downloaded was played offline (a row, Play, the queue, or a dropped stream).
        .onChange(of: signedIn.player.offlineNotice) { _, notice in
            if notice != nil { actions.showOffline() }
        }
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
        Button(action: openProfile) { TintedBarIcon(glyph: .user) }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile and Settings")
    }
}

/// A tab root's bar button icon in the tinted circle the main buttons use (Play, Shuffle),
/// instead of the bar's glass. Drawn inside the label: the bar ignores backgrounds added
/// outside a button, and turns an item holding a menu into that menu's button.
struct TintedBarIcon: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.barIconInGroup) private var inGroup
    let glyph: Glyph

    var body: some View {
        glyph.image
            .foregroundStyle(theme.palette.accent)
            // In a capsule, the plain button style dims every item alike (Labels too).
            .opacity(isEnabled || inGroup ? 1 : 0.4)
            .frame(width: 44, height: 44)
            // In a group, the group's capsule is the fill.
            .background { if !inGroup { TintedBarFill(shape: .circle) } }
            .contentShape(.circle)
    }
}

/// The main buttons' tint as it shows on the page background, but opaque, so bar buttons over
/// artwork (album and artist pages) read the same as on a plain screen.
struct TintedBarFill<S: Shape>: View {
    @Environment(\.theme) private var theme
    let shape: S

    var body: some View {
        shape.fill(theme.palette.background)
            .overlay(shape.fill(theme.palette.tint))
    }
}

/// Bar buttons side by side in one tinted capsule, each with a 44pt tap area.
struct TintedBarCapsule<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder let content: Content

    var body: some View {
        // An explicit size: the bar sizes custom items from what they report, and a stack of
        // buttons and menus reports only its first, pushing the rest off the screen.
        Group(subviews: content) { items in
            HStack(spacing: 0) {
                ForEach(items) { item in
                    item.frame(width: 44, height: 44)
                }
            }
            .frame(width: CGFloat(items.count) * 44, height: 44)
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .foregroundStyle(theme.palette.accent)
        .environment(\.barIconInGroup, true)
        .background { TintedBarFill(shape: .capsule) }
    }
}

extension View {
    /// A detail page's bar: the tinted system Back on the left and the page's buttons in one
    /// tinted capsule on the right, instead of the bar's glass. SwiftUI's bar rebuilds an item
    /// as a bar button (dropping the capsule and every button after the first), and the bar
    /// takes the taps of anything floated over it, so the capsule is a UIKit custom bar item.
    func detailBarButtons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        modifier(DetailBar(buttons: content()))
    }
}

private struct DetailBar<Buttons: View>: ViewModifier {
    @Environment(\.self) private var environment
    let buttons: Buttons

    func body(content: Content) -> some View {
        content
            .tintedSystemBack()
            .background(
                CustomBarItem(content: TintedBarCapsule { buttons }.environment(\.self, environment))
            )
    }
}

/// Puts SwiftUI content in the bar's trailing slot as it's drawn, with no glass.
private struct CustomBarItem<Content: View>: UIViewControllerRepresentable {
    let content: Content

    func makeUIViewController(context: Context) -> Controller { Controller(content: content) }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.hosting.rootView = content
    }

    final class Controller: UIViewController {
        let hosting: UIHostingController<Content>
        private lazy var item: UIBarButtonItem = {
            hosting.view.backgroundColor = .clear
            let item = UIBarButtonItem(customView: hosting.view)
            item.hidesSharedBackground = true
            return item
        }()

        init(content: Content) {
            hosting = UIHostingController(rootView: content)
            hosting.sizingOptions = .intrinsicContentSize
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            // The page's own item, so it slides in and out with the page.
            parent?.navigationItem.rightBarButtonItem = item
        }
    }
}

extension View {
    /// A list page's bar (Songs, Playlists, episode lists): a tinted Back and, if given, one
    /// tinted button or menu on the right, instead of the bar's glass. These keep the bar, so
    /// the large title and its collapse work as usual; one item per side sizes correctly.
    func listBar() -> some View {
        modifier(ListBar(trailing: EmptyView()))
    }

    func listBar<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(ListBar(trailing: trailing()))
    }

    /// The system Back, tinted instead of glass.
    fileprivate func tintedSystemBack() -> some View {
        background(TintedSystemBack())
    }
}

private struct ListBar<Trailing: View>: ViewModifier {
    let trailing: Trailing

    func body(content: Content) -> some View {
        content
            .tintedSystemBack()
            .toolbar {
                if Trailing.self != EmptyView.self {
                    ToolbarItem(placement: .topBarTrailing) {
                        trailing.buttonStyle(.plain)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
    }
}

/// Draws the system Back as a `TintedBarIcon` with no glass behind it. Keeping the system
/// Back (rather than hiding it for a button of our own) keeps everything that comes with it:
/// the edge swipe, iOS 26's swipe from anywhere on the page, and VoiceOver's escape.
private struct TintedSystemBack: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Styler(image: image)
    }

    private var image: UIImage? {
        let renderer = ImageRenderer(content: TintedBarIcon(glyph: .back).environment(\.theme, theme))
        renderer.scale = displayScale
        return renderer.uiImage?.withRenderingMode(.alwaysOriginal)
    }

    struct Styler: UIViewControllerRepresentable {
        let image: UIImage?
        func makeUIViewController(context: Context) -> Controller { Controller() }
        func updateUIViewController(_ controller: Controller, context: Context) {
            controller.image = image
            controller.apply()
        }
    }

    final class Controller: UIViewController {
        var image: UIImage?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        func apply() {
            guard let image, let navigation = navigationController, let page = parent,
                  let index = navigation.viewControllers.firstIndex(of: page), index > 0 else { return }
            // A page's Back is the previous page's back item.
            let previous = navigation.viewControllers[index - 1].navigationItem
            previous.backButtonDisplayMode = .minimal
            let item = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
            item.hidesSharedBackground = true
            previous.backBarButtonItem = item
            navigation.navigationBar.backIndicatorImage = image
            navigation.navigationBar.backIndicatorTransitionMaskImage = image
        }
    }
}

/// A tab root's trailing bar buttons in one tinted capsule, instead of the bar's glass.
struct TintedBarGroup<Content: View>: ToolbarContent {
    @ViewBuilder let content: Content

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            TintedBarCapsule { content }
        }
        .sharedBackgroundVisibility(.hidden)
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
    /// A `TintedBarIcon` inside a shared tinted capsule draws no circle of its own.
    @Entry var barIconInGroup = false
}

extension View {
    /// Chrome for a tab's root screen, applied to the content *inside* its `NavigationStack`:
    /// the profile button at top left (opens the drawer), and root reporting so the drawer's
    /// edge swipe only works at the root, never fighting the system back gesture.
    /// `trailing` adds screen buttons next to AirPlay; give them `TintedBarIcon` labels.
    /// `centersTitle` keeps the title centered (Home's wordmark); other tabs keep theirs leading.
    func tabRootChrome(centersTitle: Bool = false) -> some View {
        modifier(TabRootChrome(centersTitle: centersTitle) { EmptyView() })
    }

    func tabRootChrome<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(TabRootChrome(trailing: trailing()))
    }
}

private struct TabRootChrome<Trailing: View>: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.tabRootReporter) private var reporter
    var centersTitle = false
    let trailing: Trailing

    init(trailing: Trailing) { self.trailing = trailing }
    init(centersTitle: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.centersTitle = centersTitle
        self.trailing = trailing()
    }

    private static var itemSize: CGFloat { 44 }

    func body(content: Content) -> some View {
        content
            .toolbar {
                // Tinted circles (see `TintedBarIcon`) instead of the bar's glass.
                ToolbarItem(placement: .topBarLeading) {
                    ProfileButton()
                }
                .sharedBackgroundVisibility(.hidden)
                // AirPlay and the screen's buttons share one tinted capsule; alone, it's a circle.
                TintedBarGroup {
                    AirPlayButton(iconSize: 24, tapSize: Self.itemSize)
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
    /// `-openSection albums` (with `-tab music`) opens that Music section.
    static let openSection = UserDefaults.standard.string(forKey: "openSection").flatMap(LibrarySection.init)
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
    static let openSection: LibrarySection? = nil
    #endif
}
