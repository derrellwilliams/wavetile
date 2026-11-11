import DesignSystem
import GRDB
import Podcasts
import SwiftUI
import UniformTypeIdentifiers

/// The Podcasts tab: Continue Listening, a row of the latest episodes, Recommended for You, then
/// the library shortcuts, and nothing below (user-specified order). Latest Podcast Episodes also
/// stays on Home. The gear opens the podcast settings; the profile drawer only holds the on/off switch.
struct PodcastsView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(\.openPodcastSearch) private var openPodcastSearch
    @State private var continueListening: [EpisodeItem] = []
    @State private var latest: [EpisodeItem] = []
    @State private var recommended: [RecommendedShow] = []
    @State private var hasShows = true
    let reselects: Int
    /// Owned by the main tab view, so the player can open an episode or show here.
    @Binding var path: NavigationPath
    @State private var refreshRequests = 0
    /// Driven by `onTabReselect`: a tab tap scrolls to the top, or at the top refreshes.
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @Namespace private var zoom
    @State private var showSettings = false
    /// `-openLatestEpisode` fires once per launch, not on every refresh of the list.
    @State private var didOpenLatest = false
    @State private var showAddFeed = false
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            page
                .tabRootChrome {
                    AddPodcastMenu(showAddFeed: $showAddFeed, showImporter: $showImporter)
                    Button { showSettings = true } label: { TintedBarIcon(glyph: .settings) }
                        .accessibilityLabel("Podcast Settings")
                }
                .podcastDestinations(zoom: zoom) { path.append($0) }
        }
        .sheet(isPresented: $showSettings) {
            PodcastSettingsView()
                .presentationDetents([.large])
                .presentationBackground(theme.palette.background)
        }
        .enableInjection()
    }

    private var page: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.spacing.xxl) {
                OfflineNotice(podcasts: true)
                if !hasShows {
                    emptyState
                }
                if !continueListening.isEmpty {
                    EpisodeShelf(title: "Continue Listening", items: continueListening)
                }
                if !latest.isEmpty {
                    EpisodeShelf(title: "Latest Episodes", items: latest)
                }
                if !recommended.isEmpty {
                    ShelfSection("Recommended for You", items: recommended) { RecommendedShowLink(show: $0) }
                }
                libraryLinks
            }
            .padding(.vertical, theme.spacing.lg)
        }
        .themedBackground()
        // The offline notice (and dimming) slide in and out.
        .animatesConnectivity()
        .navigationTitle("Podcasts")
        .markRefreshable(trigger: refreshRequests) {
            // Offline there is nothing to fetch (tab tap and pull alike); the scroll to top still plays.
            guard await Connectivity.shared.hasNetwork else { return }
            await podcasts.refreshAll()
            await podcasts.refreshRecommendations()
        }
        .onTabReselect(reselects, path: $path, scrollPosition: $scrollPosition) { refreshRequests += 1 }
        // On the always-present scroll view: a task on a shelf that isn't shown never runs.
        .task { await observe(podcasts.database.continueListening()) { continueListening = $0 } }
        .task {
            await observe(podcasts.database.latestEpisodes(limit: 15)) {
                latest = $0
                if DebugFlags.openLatestEpisode, !didOpenLatest, let first = $0.first {
                    didOpenLatest = true
                    path.append(PodcastRoute.episode(id: first.id))
                }
            }
        }
        .task { await observe(podcasts.database.followedShows()) { hasShows = !$0.isEmpty } }
        .task { await observe(podcasts.database.recommendedShows()) { recommended = $0 } }
        .task { await podcasts.refreshRecommendations() }
        .sheet(isPresented: $showAddFeed) { AddFeedSheet() }
        .opmlImporter(isPresented: $showImporter, message: $importMessage)
    }

    /// The first load appears as-is; later changes animate.
    private func observe<T: Sendable & Equatable>(_ observation: GRDBObservation<T>, update: (T) -> Void) async {
        await podcasts.observe(observation, animation: theme.motion.smooth, update: update)
    }

    private var libraryLinks: some View {
        VStack(spacing: 0) {
            ForEach(EpisodeList.allCases, id: \.self) { list in
                NavigationLink(value: PodcastRoute.list(list)) {
                    LinkRow(title: list.title, glyph: list.glyph)
                }
                .buttonStyle(.plain)
                LinkRowDivider()
            }
            NavigationLink(value: PodcastRoute.shows) {
                LinkRow(title: "Shows", glyph: .collection)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, theme.spacing.screenInset)
    }

    /// Feed links and OPML import live in the + menu and Podcast Settings.
    private var emptyState: some View {
        EmptyPrompt("Find Your Shows", message: "Follow a show to see its episodes here.", button: "Find Shows") {
            openPodcastSearch()
        }
    }
}

typealias GRDBObservation<T> = ValueObservation<ValueReducers.Fetch<T>>

/// The "+" on the Podcasts tab: search, add a feed link, or import OPML.
struct AddPodcastMenu: View {
    @Environment(\.openPodcastSearch) private var openPodcastSearch
    @Binding var showAddFeed: Bool
    @Binding var showImporter: Bool

    var body: some View {
        Menu {
            Button("Search Apple Podcasts", glyph: .search) { openPodcastSearch() }
            Button("Add Show by Link", glyph: .feed) { showAddFeed = true }
            Button("Import OPML", glyph: .download) { showImporter = true }
        } label: {
            TintedBarIcon(glyph: .add)
        }
        .accessibilityLabel("Add Podcast")
    }
}

extension View {
    /// The OPML file picker; reports how many shows were added.
    func opmlImporter(isPresented: Binding<Bool>, message: Binding<String?>) -> some View {
        modifier(OPMLImporter(isPresented: isPresented, message: message))
    }
}

private struct OPMLImporter: ViewModifier {
    @Environment(PodcastsStore.self) private var podcasts
    @Binding var isPresented: Bool
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [UTType(filenameExtension: "opml") ?? .xml, .xml]) { result in
                guard case let .success(url) = result else { return }
                Task {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    // Bound the read itself, before allocating memory for an untrusted file.
                    guard let file = try? FileHandle(forReadingFrom: url) else {
                        message = "That file couldn't be read."
                        return
                    }
                    defer { try? file.close() }
                    guard let data = try? file.read(upToCount: 5_000_000), data.count < 5_000_000 else {
                        message = "That file couldn't be read."
                        return
                    }
                    message = "Importing…"
                    let added = await podcasts.importOPML(data)
                    message = added == 0 ? "No new shows found in that file." : "Added \(added) show\(added == 1 ? "" : "s")."
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil && message != "Importing…" }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            }
    }
}
