import DesignSystem
import GRDB
import Podcasts
import SwiftUI
import UniformTypeIdentifiers

/// The Podcasts tab: Continue Listening, a row of the latest episodes, then the library
/// shortcuts, and nothing below (user-specified order). Up Next in Podcasts stays on Home. The
/// gear opens the podcast settings; the profile drawer only holds the on/off switch.
struct PodcastsView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(\.openPodcastSearch) private var openPodcastSearch
    @State private var continueListening: [EpisodeItem] = []
    @State private var latest: [EpisodeItem] = []
    @State private var hasShows = true
    @State private var path = NavigationPath()
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
                    Button("Podcast Settings", glyph: .settings) { showSettings = true }
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
                if !hasShows {
                    emptyState
                }
                if !continueListening.isEmpty {
                    EpisodeShelf(title: "Continue Listening", items: continueListening)
                }
                if !latest.isEmpty {
                    EpisodeShelf(title: "Latest Episodes", items: latest)
                }
                libraryLinks
            }
            .padding(.vertical, theme.spacing.lg)
        }
        .themedBackground()
        .navigationTitle("Podcasts")
        .markRefreshable { await podcasts.refreshAll() }
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
        .sheet(isPresented: $showAddFeed) { AddFeedSheet() }
        .opmlImporter(isPresented: $showImporter, message: $importMessage)
    }

    private func observe<T: Sendable>(_ observation: GRDBObservation<T>, update: (T) -> Void) async {
        do {
            // The first load appears as-is; later changes animate.
            var loaded = false
            for try await value in podcasts.observe(observation) {
                withAnimation(loaded ? theme.motion.smooth : nil) { update(value) }
                loaded = true
            }
        } catch { Log.observationFailed(error) }
    }

    private var libraryLinks: some View {
        VStack(spacing: 0) {
            ForEach(EpisodeList.allCases, id: \.self) { list in
                NavigationLink(value: PodcastRoute.list(list)) {
                    LinkRow(title: list.title, glyph: list.glyph)
                }
                .buttonStyle(.plain)
                Divider().overlay(theme.palette.separator).padding(.leading, 28 + theme.spacing.md)
            }
            NavigationLink(value: PodcastRoute.shows) {
                LinkRow(title: "Shows", glyph: .collection)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, theme.spacing.screenInset)
    }

    private var emptyState: some View {
        EmptyState("Find Your Shows", glyph: .podcasts, message: "Search Apple Podcasts, paste a feed link, or import your subscriptions from another app.") {
            VStack(spacing: theme.spacing.sm) {
                PrimaryButton("Find Shows") { openPodcastSearch() }
                HStack(spacing: theme.spacing.sm) {
                    Button("Add by Link") { showAddFeed = true }
                    Button("Import OPML") { showImporter = true }
                }
                .buttonStyle(.tinted)
            }
            .frame(maxWidth: 280)
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
            Label("Add Podcast", glyph: .add)
        }
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
                    // OPML files are small; refuse anything absurd.
                    guard let data = try? Data(contentsOf: url), data.count < 5_000_000 else {
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
