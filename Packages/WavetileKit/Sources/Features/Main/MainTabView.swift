import DesignSystem
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
    @State private var selection: AppTab = DebugFlags.initialTab
    /// Whether each tab's navigation stack is showing its root screen (drives edge-swipe-to-open).
    @State private var atRoot: [AppTab: Bool] = [:]

    enum AppTab: String, Hashable { case home, library, downloaded, search }

    init(app: AppModel, signedIn: AppModel.SignedIn) {
        self.app = app
        self.signedIn = signedIn
        _home = State(initialValue: HomeModel(library: signedIn.library.api))
    }

    var body: some View {
        SideDrawer(isOpen: $showSettings, edgeSwipeEnabled: atRoot[selection, default: true]) {
            tabs
        } drawer: {
            SettingsDrawer(app: app, session: signedIn.session, isOpen: $showSettings)
        }
        .environment(signedIn.library)
        // Background library sync: on launch if stale (>1h); pull to refresh in Library forces one.
        .task { await signedIn.library.syncIfNeeded() }
        .enableInjection()
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab(value: .home) {
                HomeView(model: home, userName: signedIn.session.userName, showSettings: $showSettings)
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
        // Mini player is attached here once playback lands (milestone 4):
        // .tabViewBottomAccessory { MiniPlayerBar(...) }
    }
}

extension MainTabView {
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
    /// `-tab library` starts on that tab.
    static let initialTab: MainTabView.AppTab = UserDefaults.standard.string(forKey: "tab").flatMap(MainTabView.AppTab.init) ?? .home
    #else
    static let openSettings = false
    static let openFirstAlbum = false
    static let initialTab: MainTabView.AppTab = .home
    static let albumIndex = 0
    #endif
}
