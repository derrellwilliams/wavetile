import DesignSystem
import GRDB
import Library
import Podcasts
import SwiftUI
import UIKit

struct MainTabView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    let app: AppModel
    let signedIn: AppModel.SignedIn
    @State private var home: HomeModel
    @State private var searchText = ""
    @State private var showNowPlaying = false
    @State private var connectivity = Connectivity.shared
    @State private var actions = LibraryActions()
    @State private var homePath = NavigationPath()
    @State private var podcastsPath = NavigationPath()
    /// The last page the player opened, with its stack's depth right after, so opening the same
    /// page again from the player doesn't stack a copy on top of it.
    @State private var playerRoute: (route: PodcastRoute, tab: AppTab, depth: Int)?
    /// Bumped per tab when its tab is tapped while already selected: back to the root, then a refresh.
    @State private var reselects: [AppTab: Int] = [:]
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
                .environment(\.openPodcastRoute, openPodcastRoute)
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
        // On launch and return, refresh stale content (>1h) and recheck edit permissions.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            async let permissions: Void = signedIn.library.loadPermissions()
            async let music: Void = signedIn.library.syncIfNeeded()
            async let podcasts: Void = signedIn.podcasts.refreshIfNeeded()
            _ = await (permissions, music, podcasts)
        }
        .enableInjection()
    }

    private var tabs: some View {
        TabView(selection: tabSelection) {
            Tab(value: .home) {
                HomeView(model: home, path: $homePath, reselects: reselects[.home, default: 0], userName: signedIn.session.userName, upNext: signedIn.podcasts.launchUpNext)
                    .environment(\.tabRootReporter, reporter(for: .home))
            } label: {
                tabLabel("Home", icon: Image(uiImage: WavetileMark.uiImage(color: theme.palette.accent)))
            }
            Tab(value: .music) {
                LibraryView(reselects: reselects[.music, default: 0])
                    .environment(\.tabRootReporter, reporter(for: .music))
            } label: {
                tabLabel("Music", glyph: .library)
            }
            // Opt-in from the profile drawer; music-only users never see it.
            if signedIn.podcasts.isEnabled {
                Tab(value: .podcasts) {
                    PodcastsView(reselects: reselects[.podcasts, default: 0], path: $podcastsPath)
                        .environment(\.tabRootReporter, reporter(for: .podcasts))
                } label: {
                    tabLabel("Podcasts", glyph: .podcasts)
                }
            }
            Tab(value: .downloaded) {
                DownloadedView(reselects: reselects[.downloaded, default: 0])
                    .environment(\.tabRootReporter, reporter(for: .downloaded))
            } label: {
                tabLabel("Downloads", glyph: .downloads)
            }
            Tab(value: .search, role: .search) {
                SearchView(text: $searchText, scope: $searchScope, reselects: reselects[.search, default: 0])
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

    /// The tab selection; TabView sets it again when the selected tab is tapped, which
    /// means back to the root and, where the tab refreshes, a refresh.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { tab in
                if tab == selection { reselects[tab, default: 0] += 1 }
                selection = tab
            }
        )
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

    /// From the player: closes it and opens the route on the Podcasts tab's stack (Home's when
    /// podcasts are off), on top of whatever is open there.
    fileprivate func openPodcastRoute(_ route: PodcastRoute) {
        showNowPlaying = false
        showSettings = false
        let tab: AppTab = signedIn.podcasts.isEnabled ? .podcasts : .home
        selection = tab
        let depth = tab == .podcasts ? podcastsPath.count : homePath.count
        if let last = playerRoute, last.route == route, last.tab == tab, last.depth == depth { return }
        if tab == .podcasts { podcastsPath.append(route) } else { homePath.append(route) }
        playerRoute = (route, tab, depth + 1)
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

    /// Icon only; the title is VoiceOver's name for the tab.
    private func tabLabel(_ title: String, glyph: Glyph) -> some View {
        tabLabel(title, icon: glyph.image(color: theme.palette.accent))
    }

    private func tabLabel(_ title: String, icon: Image) -> some View {
        // The glass tab bar forces template colors, so icons come with the accent baked in.
        icon.accessibilityLabel(title)
    }

    private func reporter(for tab: AppTab) -> TabRootReporter {
        TabRootReporter { isRoot in atRoot[tab] = isRoot }
    }
}

/// Profile button at top left, a tinted circle like every other bar button.
struct ProfileButton: View {
    @Environment(\.openProfile) private var openProfile

    var body: some View {
        Button(action: openProfile) { TintedBarIcon(glyph: .user) }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile and Settings")
    }
}

/// A bar button's icon on a circle of Apple's standard glass (iOS 27), or in the tinted circle
/// the main buttons use (Play, Shuffle) on iOS 26. Drawn inside the
/// label: the bar ignores backgrounds added outside a button, and turns an item holding a
/// menu into that menu's button.
struct TintedBarIcon: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.barIconInGroup) private var inGroup
    let glyph: Glyph
    /// Just the icon on a plain 44pt square, for drawing it outside the bar (the system Back).
    /// It's drawn as this view, not by reading `icon` off a bare instance: the environment
    /// (theme, enabled) is only read once the view is installed, and a bare instance reads the defaults.
    var plain = false

    var body: some View {
        if plain {
            icon
        } else {
            icon
                // In a group, the group's capsule is the button.
                .modifier(BarButtonShape(shape: .circle, width: TintedBar.size, isOn: !inGroup))
        }
    }

    private var icon: some View {
        glyph.image
            .foregroundStyle(theme.palette.accent)
            // In a capsule, the plain button style and `DimmingMenuStyle` dim each item.
            .opacity(isEnabled || inGroup ? 1 : 0.4)
            .frame(width: TintedBar.size, height: TintedBar.size)
    }
}

/// Bar button metrics.
enum TintedBar {
    static let size: CGFloat = 44
    /// iOS 27 buttons are Apple's standard glass, drawn on the button rather than by the bar:
    /// the bar's glass is wider than an item (a pill around a 44pt button), so it's hidden and
    /// each button draws its own circle (or capsule, for a group). iOS 26 draws a tinted circle.
    static var drawsGlass: Bool {
        if #available(iOS 27, *) { true } else { false }
    }

    /// The bar's own glass behind an item: always hidden; buttons draw their own.
    static let glass: Visibility = .hidden
}

/// Sizes an item `width` wide and gives it its glass (or, on iOS 26, its tinted fill).
private struct BarButtonShape<S: Shape>: ViewModifier {
    let shape: S
    let width: CGFloat
    var isOn = true

    func body(content: Content) -> some View {
        if isOn {
            let sized = content
                .frame(width: width, height: TintedBar.size)
                .contentShape(shape)
            if TintedBar.drawsGlass {
                sized.glassEffect(.regular.interactive(), in: shape)
            } else {
                sized.background { TintedBarFill(shape: shape) }
            }
        } else {
            content
        }
    }
}

/// A sheet's Close, Cancel or Done as a bar button (see `TintedBarIcon`).
struct TintedSheetButton: ToolbarContent {
    let title: String
    let glyph: Glyph
    let placement: ToolbarItemPlacement
    let action: () -> Void

    init(_ title: String, glyph: Glyph, placement: ToolbarItemPlacement, action: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph
        self.placement = placement
        self.action = action
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            Button(action: action) { TintedBarIcon(glyph: glyph) }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
        }
        .sharedBackgroundVisibility(TintedBar.glass)
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
            if !items.isEmpty {
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        item.frame(width: TintedBar.size, height: TintedBar.size)
                    }
                }
                .modifier(BarButtonShape(shape: .capsule, width: CGFloat(items.count) * TintedBar.size))
            }
        }
        .buttonStyle(.plain)
        .menuStyle(DimmingMenuStyle())
        .labelStyle(.iconOnly)
        .foregroundStyle(theme.palette.accent)
        .environment(\.barIconInGroup, true)
    }
}

/// Dims a disabled menu the way the plain button style dims a disabled button, so every item
/// in a capsule dims alike.
private struct DimmingMenuStyle: MenuStyle {
    func makeBody(configuration: MenuStyleConfiguration) -> some View {
        DimmingMenu(configuration: configuration)
    }
}

private struct DimmingMenu: View {
    @Environment(\.isEnabled) private var isEnabled
    let configuration: MenuStyleConfiguration

    var body: some View {
        Menu(configuration).opacity(isEnabled ? 1 : 0.4)
    }
}

extension View {
    /// A detail page's bar: the tinted system Back on the left and the page's buttons in one
    /// capsule on the right. SwiftUI's bar rebuilds an item
    /// as a bar button (dropping the capsule and every button after the first), and the bar
    /// takes the taps of anything floated over it, so the capsule is a UIKit custom bar item.
    func detailBarButtons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        modifier(DetailBar(buttons: content()))
    }
}

private struct DetailBar<Buttons: View>: ViewModifier {
    let buttons: Buttons

    func body(content: Content) -> some View {
        content
            .tintedSystemBack()
            .background(CustomBarItem(content: TintedBarCapsule { buttons }))
    }
}

/// Puts SwiftUI content in the bar's trailing slot as it's drawn, over the bar's glass.
private struct CustomBarItem<Content: View>: UIViewControllerRepresentable {
    let content: Content

    func makeUIViewController(context: Context) -> Controller {
        Controller(content: Hosted(content: content, environment: context.environment))
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        // The hosting controller sits outside this view tree, so it gets the environment
        // (theme, stores) passed in; read here, so only this item updates when it changes.
        controller.update(Hosted(content: content, environment: context.environment))
    }

    struct Hosted: View {
        let content: Content
        let environment: EnvironmentValues
        var body: some View { content.environment(\.self, environment) }
    }

    final class Controller: UIViewController {
        private let hosting: UIHostingController<Hosted>
        /// The bar item and the view it holds. A new pair for each width: the bar places a custom
        /// item once, from its first size, so a wider capsule in the same item would hang off the
        /// right edge.
        private var slot: (item: UIBarButtonItem, container: SizedBarView)?
        /// True from taking the old item out until the bar has laid out without it.
        private var isReplacing = false

        init(content: Hosted) {
            hosting = UIHostingController(rootView: content)
            hosting.sizingOptions = .intrinsicContentSize
            // Not a child view controller: its view lives in the bar, outside this one's, and
            // UIKit throws on that hierarchy. The environment, passed in, carries traits.
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError() }

        private var fittingSize: CGSize { hosting.sizeThatFits(in: UIView.layoutFittingExpandedSize) }

        private func makeSlot(size: CGSize) -> (item: UIBarButtonItem, container: SizedBarView) {
            let container = SizedBarView(size: size)
            hosting.view.backgroundColor = .clear
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hosting.view.frame = container.bounds
            container.addSubview(hosting.view)
            let item = UIBarButtonItem(customView: container)
            item.hidesSharedBackground = true
            return (item, container)
        }

        func update(_ content: Hosted) {
            hosting.rootView = content
            // Buttons can arrive after the page loads (an episode, a show's settings).
            let size = fittingSize
            if let current = slot, current.container.size != size {
                if let page = parent, page.navigationItem.rightBarButtonItem === current.item {
                    page.navigationItem.rightBarButtonItem = nil
                    // Put the new item in on the next turn, once the bar has laid out without
                    // the old one, so it isn't placed from the old one's spot.
                    isReplacing = true
                    DispatchQueue.main.async { [weak self] in
                        self?.isReplacing = false
                        self?.install()
                    }
                }
                slot = makeSlot(size: size)
            }
            install()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            install()
        }

        /// The page's own item, so it slides in and out with the page. SwiftUI also writes the
        /// page's bar items (its toolbar), so this puts the capsule back if they replaced it.
        private func install() {
            guard let page = parent, !isReplacing else { return }
            let size = fittingSize
            // No buttons (an episode still loading): no item, so no empty glass.
            var wanted: UIBarButtonItem?
            if size.width > 0 {
                if slot == nil { slot = makeSlot(size: size) }
                wanted = slot?.item
            }
            guard page.navigationItem.rightBarButtonItem !== wanted else { return }
            page.navigationItem.rightBarButtonItem = wanted
        }
    }
}

/// A custom bar item's view, reporting the size the bar lays it out at.
private final class SizedBarView: UIView {
    let size: CGSize

    init(size: CGSize) {
        self.size = size
        super.init(frame: CGRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { size }
}

extension View {
    /// A list page's bar (Songs, Playlists, episode lists): a tinted Back and, if given, one
    /// button or menu on the right. These keep the bar, so
    /// the large title and its collapse work as usual; one item per side sizes correctly.
    func listBar() -> some View {
        modifier(ListBar(trailing: EmptyView()))
    }

    /// `showsTrailing` false leaves the right side empty (an `if` in the builder would still
    /// make an item, and the bar would draw empty glass for it).
    func listBar<Trailing: View>(showsTrailing: Bool = true, @ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(ListBar(trailing: trailing(), showsTrailing: showsTrailing))
    }

    /// The system Back, with the tan chevron (and on iOS 26, the tinted circle).
    func tintedSystemBack() -> some View {
        background(TintedSystemBack())
    }
}

private struct ListBar<Trailing: View>: ViewModifier {
    let trailing: Trailing
    var showsTrailing = true

    func body(content: Content) -> some View {
        content
            .tintedSystemBack()
            .toolbar {
                if showsTrailing, Trailing.self != EmptyView.self {
                    ToolbarItem(placement: .topBarTrailing) {
                        trailing.buttonStyle(.plain)
                    }
                    .sharedBackgroundVisibility(TintedBar.glass)
                }
            }
    }
}

/// Draws the system Back as a `TintedBarIcon`, over the glass iOS keeps behind it. Keeping the system Back (rather than hiding it for a button of our
/// own) keeps everything that comes with it:
/// the edge swipe, iOS 26's swipe from anywhere on the page, and VoiceOver's escape.
/// The chevron image belongs to the whole bar, so every page in the stack is styled (tab roots
/// too, via `tabRootChrome`), each before anything is pushed from it.
private struct TintedSystemBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.style = Style(
            theme: context.environment.theme,
            colorScheme: context.environment.colorScheme,
            scale: context.environment.displayScale
        )
        controller.apply()
    }

    struct Style: Hashable {
        let theme: Theme
        let colorScheme: ColorScheme
        let scale: CGFloat

        @MainActor func render() -> UIImage? {
            let renderer = ImageRenderer(content: TintedBarIcon(glyph: .back, plain: true)
                .background {
                    if !TintedBar.drawsGlass { TintedBarFill(shape: .circle) }
                }
                .environment(\.theme, theme)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = scale
            return renderer.uiImage?.withRenderingMode(.alwaysOriginal)
        }
    }

    final class Controller: UIViewController {
        var style: Style?
        /// Rendered once per style, not on every update.
        private var rendered: (style: Style, image: UIImage)?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        /// Again once the push lands, in case SwiftUI rewrote the page's appearances meanwhile.
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        func apply() {
            guard let style, let navigation = navigationController else { return }
            if rendered?.style != style, let image = style.render() { rendered = (style, image) }
            guard let image = rendered?.image else { return }
            let bar = navigation.navigationBar
            // For any page without appearances of its own, and any bar appearance left unset.
            if bar.backIndicatorImage !== image {
                bar.backIndicatorImage = image
                bar.backIndicatorTransitionMaskImage = image
            }
            // The chevron comes from the bar's appearances (SwiftUI sets the bar's and a page's
            // own), which win over `backIndicatorImage`, so it's set on each of them. Each is
            // written only when its chevron differs, so updates don't restyle the bar.
            var changed = false
            if let new = tinted(bar.standardAppearance, image) { bar.standardAppearance = new; changed = true }
            if let new = tinted(bar.scrollEdgeAppearance, image) { bar.scrollEdgeAppearance = new; changed = true }
            if let new = tinted(bar.compactAppearance, image) { bar.compactAppearance = new; changed = true }
            for page in navigation.viewControllers {
                let item = page.navigationItem
                // A page's Back is the previous page's back item: the chevron alone.
                if item.backButtonDisplayMode != .minimal { item.backButtonDisplayMode = .minimal }
                if let new = tinted(item.standardAppearance, image) { item.standardAppearance = new; changed = true }
                if let new = tinted(item.scrollEdgeAppearance, image) { item.scrollEdgeAppearance = new; changed = true }
                if let new = tinted(item.compactAppearance, image) { item.compactAppearance = new; changed = true }
            }
            // A swap mid-transition could leave the large title laid out without its side margin
            // until the next layout pass; lay the bar out again right away.
            if changed {
                bar.setNeedsLayout()
                bar.layoutIfNeeded()
            }
        }

        /// A copy of `appearance` with `image` as its chevron and the brand titles (SwiftUI's
        /// appearances ignore the title proxy), or nil if it has both already (or there's no appearance).
        private func tinted(_ appearance: UINavigationBarAppearance?, _ image: UIImage) -> UINavigationBarAppearance? {
            let largeTitleFont = BrandFont.largeTitleAttributes[.font] as? UIFont
            guard let appearance,
                  appearance.backIndicatorImage !== image
                  || appearance.largeTitleTextAttributes[.font] as? UIFont != largeTitleFont
            else { return nil }
            let copy = appearance.copy()
            copy.setBackIndicatorImage(image, transitionMaskImage: image)
            copy.largeTitleTextAttributes = BrandFont.largeTitleAttributes
            copy.titleTextAttributes = BrandFont.titleAttributes
            return copy
        }
    }
}

/// A tab root's trailing bar buttons in one capsule.
struct TintedBarGroup<Content: View>: ToolbarContent {
    @ViewBuilder let content: Content

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            TintedBarCapsule { content }
        }
        .sharedBackgroundVisibility(TintedBar.glass)
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
    /// A tap on the already-selected tab (`reselects` counts them), one step per tap, never two
    /// at once: from a pushed screen, back to the tab's root; at the root but scrolled down, to
    /// the top; at the top, `refresh`. Binds `scrollPosition` to the tab's scroll view and tracks
    /// whether it is at the top. Attach it to the scroll view (Search: to the container of its
    /// lists). A tab with no `refresh` scrolls on every tap, so a stale at-top value (a scroll
    /// view swapped out) can't swallow one.
    func onTabReselect(_ reselects: Int, path: Binding<NavigationPath>, scrollPosition: Binding<ScrollPosition>, refresh: (() -> Void)? = nil) -> some View {
        modifier(TabReselect(reselects: reselects, path: path, scrollPosition: scrollPosition, refresh: refresh))
    }

    /// Chrome for a tab's root screen, applied to the content *inside* its `NavigationStack`:
    /// the profile button at top left (opens the drawer), and root reporting so the drawer's
    /// edge swipe only works at the root, never fighting the system back gesture.
    /// `showsWave` centers the wave in the bar (Home only); `onWaveTap` makes it a button. `trailing` adds screen buttons next
    /// to AirPlay; give them `TintedBarIcon` labels.
    func tabRootChrome(showsWave: Bool = false, onWaveTap: (() -> Void)? = nil) -> some View {
        modifier(TabRootChrome(showsWave: showsWave, onWaveTap: onWaveTap, trailing: EmptyView()))
    }

    func tabRootChrome<Trailing: View>(showsWave: Bool = false, onWaveTap: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(TabRootChrome(showsWave: showsWave, onWaveTap: onWaveTap, trailing: trailing()))
    }
}

private struct TabRootChrome<Trailing: View>: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.tabRootReporter) private var reporter
    let showsWave: Bool
    let onWaveTap: (() -> Void)?
    let trailing: Trailing

    private static var itemSize: CGFloat { 44 }

    func body(content: Content) -> some View {
        content
            .toolbar {
                // Bar buttons (see `TintedBarIcon`).
                ToolbarItem(placement: .topBarLeading) {
                    ProfileButton()
                }
                .sharedBackgroundVisibility(TintedBar.glass)
                // The wave, centered in Home's bar.
                if showsWave {
                    ToolbarItem(placement: .principal) {
                        if let onWaveTap {
                            Button(action: onWaveTap) {
                                WaveMark(width: 104)
                                    .frame(height: Self.itemSize)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Wavetile")
                            .accessibilityHint("Scrolls to the top")
                        } else {
                            WaveMark(width: 104)
                                .accessibilityElement()
                                .accessibilityLabel("Wavetile")
                        }
                    }
                }
                // AirPlay and the screen's buttons share one capsule; alone, it's a circle.
                TintedBarGroup {
                    AirPlayButton(iconSize: 24, tapSize: Self.itemSize)
                    trailing
                }
            }
            // Styles the root's back item before anything is pushed from it.
            .tintedSystemBack()
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

/// See `View.onTabReselect`.
private struct TabReselect: ViewModifier {
    @Environment(\.theme) private var theme
    let reselects: Int
    @Binding var path: NavigationPath
    @Binding var scrollPosition: ScrollPosition
    let refresh: (() -> Void)?
    @State private var isAtTop = true

    func body(content: Content) -> some View {
        content
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Pulled past the top (a refresh in progress) counts as the top.
                geometry.contentOffset.y + geometry.contentInsets.top <= 2
            } action: { _, atTop in
                isAtTop = atTop
            }
            .onChange(of: reselects) {
                if !path.isEmpty {
                    path = NavigationPath()
                } else if let refresh, isAtTop {
                    refresh()
                } else {
                    withAnimation(theme.motion.smooth) { scrollPosition.scrollTo(edge: .top) }
                }
            }
    }
}
