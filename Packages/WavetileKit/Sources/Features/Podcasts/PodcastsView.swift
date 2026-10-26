import DesignSystem
import GRDB
import Podcasts
import SwiftUI
import UniformTypeIdentifiers

/// The Podcasts page in Library: library shortcuts, latest episodes, your shows and top charts,
/// modeled on Apple Podcasts' Library. (Continue Listening and Up Next live on Home.)
struct PodcastsView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(\.openPodcastSearch) private var openPodcastSearch
    @State private var latest: [EpisodeItem] = []
    @State private var shows: [ShowSummary] = []
    @State private var didLoad = false
    @State private var showAddFeed = false
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.spacing.xxl) {
                if didLoad && shows.isEmpty {
                    emptyState
                }
                libraryLinks
                if !latest.isEmpty {
                    latestSection
                }
                if !shows.isEmpty {
                    showsShelf
                }
                TopShowsShelf()
            }
            .padding(.vertical, theme.spacing.lg)
        }
        .themedBackground()
        .navigationTitle("Podcasts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AddPodcastMenu(showAddFeed: $showAddFeed, showImporter: $showImporter)
            }
        }
        .markRefreshable { await podcasts.refreshAll() }
        .task { await observe(podcasts.database.latestEpisodes(limit: 5)) { latest = $0 } }
        // Here, not on the shelf: the shelf only exists once the chart has loaded.
        .task { await podcasts.loadTopShows() }
        .task {
            await observe(podcasts.database.followedShows()) {
                shows = $0
                didLoad = true
            }
        }
        .sheet(isPresented: $showAddFeed) { AddFeedSheet() }
        .opmlImporter(isPresented: $showImporter, message: $importMessage)
        .enableInjection()
    }

    private func observe<T: Sendable>(_ observation: GRDBObservation<T>, update: (T) -> Void) async {
        do {
            for try await value in podcasts.observe(observation) {
                withAnimation(theme.motion.smooth) { update(value) }
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

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Latest Episodes", destination: .list(.latest))
            LazyVStack(spacing: 0) {
                ForEach(latest) { item in
                    EpisodeRow(item: item)
                    Divider().overlay(theme.palette.separator)
                }
            }
            .padding(.horizontal, theme.spacing.screenInset)
        }
    }

    private var showsShelf: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(title: "Your Shows", destination: .shows)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: theme.spacing.lg) {
                    ForEach(shows) { summary in
                        NavigationLink(value: PodcastRoute.show(ShowRoute(summary.show))) {
                            ShowTile(title: summary.show.title, subtitle: summary.show.author, artworkURL: summary.show.artworkURL, newCount: summary.newCount)
                        }
                        .buttonStyle(.pressable)
                        .frame(width: theme.artwork.shelfTileWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, theme.spacing.screenInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    private var emptyState: some View {
        EmptyState("Find Your Shows", glyph: .podcasts, message: "Search Apple Podcasts, paste a feed link, or import your subscriptions from another app.") {
            VStack(spacing: theme.spacing.sm) {
                PrimaryButton("Find Shows") { openPodcastSearch() }
                HStack(spacing: theme.spacing.sm) {
                    Button("Add by Link") { showAddFeed = true }
                    Button("Import OPML") { showImporter = true }
                }
                .buttonStyle(.glass)
            }
            .frame(maxWidth: 280)
        }
    }
}

typealias GRDBObservation<T> = ValueObservation<ValueReducers.Fetch<T>>

/// A section title, optionally with a "See All" link.
struct SectionHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    var destination: PodcastRoute?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(theme.typography.sectionHeader)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let destination {
                NavigationLink("See All", value: destination)
                    .font(theme.typography.itemSubtitle.weight(.semibold))
                    .foregroundStyle(theme.palette.accent)
            }
        }
        .padding(.horizontal, theme.spacing.screenInset)
    }
}

/// A Library-style row: glyph, title, chevron.
struct LinkRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let glyph: Glyph

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            glyph.image
                .foregroundStyle(theme.palette.accent)
                .frame(width: 28)
            Text(title)
                .font(theme.typography.sectionHeader)
                .foregroundStyle(theme.palette.textPrimary)
            Spacer()
            Glyph.chevron.image
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(theme.palette.textSecondary)
        }
        .padding(.vertical, theme.spacing.md + 2)
        .contentShape(.rect)
    }
}

/// The "+" on the Podcasts page: search, add a feed link, or import OPML.
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

/// Apple's top shows, as a shelf.
struct TopShowsShelf: View {
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts

    var body: some View {
        Group {
            if !podcasts.topShows.isEmpty {
                VStack(alignment: .leading, spacing: theme.spacing.md) {
                    SectionHeader(title: "Top Shows", destination: .topShows)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: theme.spacing.lg) {
                            ForEach(podcasts.topShows.prefix(15)) { show in
                                if let route = ShowRoute(show) {
                                    NavigationLink(value: PodcastRoute.show(route)) {
                                        ShowTile(title: show.title, subtitle: show.author, artworkURL: show.artworkURL)
                                    }
                                    .buttonStyle(.pressable)
                                    .frame(width: theme.artwork.shelfTileWidth)
                                }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, theme.spacing.screenInset, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                }
            }
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
