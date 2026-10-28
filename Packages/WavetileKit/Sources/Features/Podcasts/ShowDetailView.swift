import DesignSystem
import Playback
import Podcasts
import SwiftUI

/// A show's page: art, title, Follow, play latest, description, settings, episodes (with
/// seasons and search) and similar shows.
/// Shows reached from search load as previews until followed.
struct ShowDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(AudioPlayer.self) private var player
    let route: ShowRoute
    @State private var show: ShowRecord?
    @State private var episodes: [EpisodeItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isFollowing = false
    @State private var confirmMarkAll = false
    /// nil shows every season.
    @State private var season: Int?
    @State private var query = ""
    @State private var similar: [DirectoryShow] = []

    private var showID: String { PodcastID.show(feedURL: route.feedURL) }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.xl) {
                VStack(spacing: theme.spacing.md) {
                    // Same as an episode: a smaller square over a blur of the art.
                    ArtworkSpotlight(artwork: .unsized(show?.artworkURL ?? route.artworkURL, maxPixelWidth: 720))
                    header
                }
                content
                if !similar.isEmpty {
                    ShelfSection("You Might Also Like", items: similar) { show in
                        SimilarShowLink(show: show)
                    }
                }
            }
            .padding(.bottom, theme.spacing.xxl)
        }
        // The blurred art runs under the navigation bar: no bar background or blur band.
        .detailPageChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { followButton }
            if let show {
                ToolbarItem(placement: .topBarTrailing) { settingsMenu(show) }
            }
        }
        .confirmationDialog("Mark every episode as played?", isPresented: $confirmMarkAll, titleVisibility: .visible) {
            Button("Mark All as Played") { if let show { podcasts.markAllPlayed(show) } }
        }
        .refreshable { if let show { await podcasts.refresh(show) } }
        .task { await load() }
        .task {
            let found = (try? await podcasts.directory.similarShows(title: route.title, feedURL: route.feedURL)) ?? []
            withAnimation(theme.motion.smooth) { similar = found }
        }
        .task(id: show.map { "\($0.sortsOldestFirst)\($0.hidePlayed)" }) { await observeEpisodes() }
        .enableInjection()
    }

    private func load() async {
        do {
            let loaded = try await podcasts.loadShow(feedURL: route.feedURL)
            podcasts.markOpened(loaded)
            for try await value in podcasts.observe(podcasts.database.show(id: loaded.id)) {
                show = value
                isFollowing = value?.isFollowed ?? false
                isLoading = false
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func observeEpisodes() async {
        guard let show else { return }
        do {
            let observation = podcasts.database.episodes(showID: show.id, oldestFirst: show.sortsOldestFirst, hidePlayed: show.hidePlayed)
            for try await value in podcasts.observe(observation) { episodes = value }
        } catch { Log.observationFailed(error) }
    }

    private var header: some View {
        VStack(spacing: theme.spacing.md) {
            DetailHeader(show?.title ?? route.title, metadata: metadata) {
                if !(show?.author ?? route.author).isEmpty {
                    DetailSubtitle(show?.author ?? route.author)
                }
            }
            VStack(spacing: theme.spacing.md) {
                PrimaryButton(playTitle, glyph: .play) { if let item = playTarget { podcasts.play(item) } }
                    .disabled(playTarget == nil)
                if let summary = show?.summary, !summary.isEmpty {
                    ExpandableText(summary)
                }
            }
            .padding(.horizontal, theme.spacing.screenInset)
        }
    }

    /// In the toolbar, as in Apple Podcasts: + to follow, a check once following.
    private var followButton: some View {
        Button {
            guard let show else { return }
            let target = !isFollowing
            withAnimation(theme.motion.snappy) { isFollowing = target }
            Task { await podcasts.setFollowed(show, target) }
        } label: {
            Label(isFollowing ? "Following" : "Follow", glyph: isFollowing ? .check : .add)
                .contentTransition(.symbolEffect(.replace))
        }
        .disabled(show == nil)
        .sensoryFeedback(.success, trigger: isFollowing) { _, new in new }
    }

    /// Serial shows start from the first unplayed episode; others from the newest.
    private var playTarget: EpisodeItem? {
        if let resume = episodes.first(where: { $0.episode.isInProgress }) { return resume }
        let ordered = show?.isSerial == true
            ? episodes.sorted { ($0.episode.publishedAt ?? .distantPast) < ($1.episode.publishedAt ?? .distantPast) }
            : episodes.sorted { ($0.episode.publishedAt ?? .distantPast) > ($1.episode.publishedAt ?? .distantPast) }
        return ordered.first { !$0.episode.isPlayed } ?? ordered.first
    }

    private var playTitle: LocalizedStringKey {
        guard let target = playTarget else { return "Play" }
        if target.episode.isInProgress { return "Resume" }
        return show?.isSerial == true ? "Play First" : "Play Latest"
    }

    private var metadata: String? {
        guard !episodes.isEmpty else { return nil }
        var parts = ["\(episodes.count) episode\(episodes.count == 1 ? "" : "s")"]
        if let frequency { parts.append(frequency) }
        if show?.isSerial == true { parts.append("Series") }
        if let rate = show?.playbackRate, rate != 1 { parts.append("\(rate.formatted())× speed") }
        return parts.joined(separator: " · ")
    }

    /// How often new episodes arrive, from the gaps between the last ten. Nothing for shows
    /// that have gone quiet or are too new to tell.
    private var frequency: String? {
        let dates = episodes.compactMap(\.episode.publishedAt).sorted(by: >).prefix(11)
        guard dates.count >= 3, let latest = dates.first, latest.timeIntervalSinceNow > -60 * 86400 else { return nil }
        let gaps = zip(dates, dates.dropFirst()).map { $0.timeIntervalSince($1) / 86400 }.sorted()
        return switch gaps[gaps.count / 2] {
        case ..<1.5: "Daily"
        case ..<4.5: "Twice weekly"
        case ..<10: "Weekly"
        case ..<20: "Every two weeks"
        case ..<45: "Monthly"
        default: nil
        }
    }

    /// Seasons, when the feed numbers more than one.
    private var seasons: [Int] {
        let numbers = Set(episodes.compactMap(\.episode.season))
        return numbers.count > 1 ? numbers.sorted() : []
    }

    /// The list after the season picker and search.
    private var visibleEpisodes: [EpisodeItem] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return episodes.filter { item in
            (season == nil || item.episode.season == season)
                && (text.isEmpty || item.episode.title.localizedStandardContains(text) || item.episode.summary.localizedStandardContains(text))
        }
    }

    @ViewBuilder private var content: some View {
        if isLoading && episodes.isEmpty {
            LoadingMark().padding(theme.spacing.xxl)
        } else if let errorMessage, episodes.isEmpty {
            EmptyState("Couldn't Load Show", glyph: .warning, message: errorMessage) {
                Button("Retry") {
                    self.errorMessage = nil
                    isLoading = true
                    Task { await load() }
                }
                .buttonStyle(.tinted)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Episodes")
                        .font(theme.typography.sectionHeader)
                        .foregroundStyle(theme.palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if show?.hidePlayed == true {
                        Text("Unplayed")
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    if !seasons.isEmpty { seasonMenu }
                }
                if episodes.count >= 8 {
                    EpisodeSearchField(text: $query)
                        .padding(.top, theme.spacing.md)
                }
                ForEach(visibleEpisodes) { item in
                    EpisodeRow(item: item, showsArtwork: false)
                    Divider().overlay(theme.palette.separator)
                }
                if !episodes.isEmpty, visibleEpisodes.isEmpty {
                    Text("No episodes match.")
                        .font(theme.typography.itemSubtitle)
                        .foregroundStyle(theme.palette.textSecondary)
                        .padding(.vertical, theme.spacing.xl)
                }
                if episodes.isEmpty {
                    Text(show?.hidePlayed == true ? "You've played every episode." : "No episodes yet.")
                        .font(theme.typography.itemSubtitle)
                        .foregroundStyle(theme.palette.textSecondary)
                        .padding(.vertical, theme.spacing.xl)
                }
            }
            .padding(.horizontal, theme.spacing.screenInset)
        }
    }

    private var seasonMenu: some View {
        Menu {
            Picker("Season", selection: $season.animation(theme.motion.smooth)) {
                Text("All Seasons").tag(Int?.none)
                ForEach(seasons, id: \.self) { number in
                    Text("Season \(number)").tag(Int?.some(number))
                }
            }
        } label: {
            Text(season.map { "Season \($0)" } ?? "All Seasons")
        }
        .buttonStyle(.tinted(.small))
    }

    private func settingsMenu(_ show: ShowRecord) -> some View {
        Menu {
            Picker("Order", selection: Binding(
                get: { show.sortsOldestFirst },
                set: { value in podcasts.updateShow(show) { $0.oldestFirst = value } }
            )) {
                Text("Newest First").tag(false)
                Text("Oldest First").tag(true)
            }
            Toggle(isOn: Binding(get: { show.hidePlayed }, set: { value in podcasts.updateShow(show) { $0.hidePlayed = value } })) {
                Label("Hide Played Episodes", glyph: .hidePlayed)
            }
            Menu {
                Picker("Speed", selection: Binding(
                    get: { show.playbackRate },
                    set: { value in podcasts.updateShow(show) { $0.playbackRate = value } }
                )) {
                    Text("Default (\(podcasts.defaultRate.formatted())×)").tag(Double?.none)
                    ForEach(AudioPlayer.podcastRates, id: \.self) { rate in
                        Text("\(Double(rate).formatted())×").tag(Double?.some(Double(rate)))
                    }
                }
            } label: {
                Label("Playback Speed", glyph: .speed)
            }
            if show.isFollowed {
                Toggle(isOn: Binding(get: { show.autoDownload }, set: { value in podcasts.updateShow(show) { $0.autoDownload = value } })) {
                    Label("Auto-Download", glyph: .download)
                }
                .disabled(podcasts.autoDownloadCount == 0)
            }
            Divider()
            Button("Mark All as Played", glyph: .check) { confirmMarkAll = true }
            ShareLink(item: show.websiteURL ?? show.feedURL) {
                Label("Share Show", glyph: .share)
            }
            Button("Copy Feed Link", glyph: .copy) { UIPasteboard.general.url = show.feedURL }
            if show.isFollowed {
                Divider()
                Button("Unfollow", glyph: .close, role: .destructive) {
                    isFollowing = false
                    Task { await podcasts.setFollowed(show, false) }
                }
            }
        } label: {
            Label("Show Settings", glyph: .more)
        }
    }
}

/// Every followed show, as a grid.
/// A filter field for a show's episodes, matching titles and summaries.
private struct EpisodeSearchField: View {
    @Environment(\.theme) private var theme
    @Binding var text: String

    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            Glyph.search.image
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundStyle(theme.palette.textSecondary)
            TextField("Search Episodes", text: $text)
                .font(theme.typography.body)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                GlyphButton("Clear Search", glyph: .close, size: 14) { text = "" }
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .padding(.horizontal, theme.spacing.md)
        .frame(minHeight: 44)
        .background(theme.palette.surface, in: .capsule)
    }
}

/// A directory show in the "You Might Also Like" shelf; opens as a preview until followed.
private struct SimilarShowLink: View {
    @Environment(\.zoomNamespace) private var zoom
    let show: DirectoryShow

    private var sourceID: String { "similar-\(show.id)" }

    var body: some View {
        if let route {
            NavigationLink(value: PodcastRoute.show(route)) {
                ShowTile(title: show.title, subtitle: show.author, artworkURL: show.artworkURL)
                    .zoomSource(sourceID, in: zoom)
            }
            .buttonStyle(.pressable)
        }
    }

    private var route: ShowRoute? {
        var route = ShowRoute(show)
        route?.sourceID = sourceID
        return route
    }
}

struct AllShowsView: View {
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(\.zoomNamespace) private var zoom
    @State private var shows: [ShowSummary] = []

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: theme.artwork.shelfTileWidth - 8), spacing: theme.spacing.lg)],
                alignment: .leading,
                spacing: theme.spacing.xl
            ) {
                ForEach(shows) { summary in
                    NavigationLink(value: PodcastRoute.show(zoomRoute(summary.show))) {
                        ShowTile(title: summary.show.title, subtitle: summary.show.author, artworkURL: summary.show.artworkURL, newCount: summary.newCount)
                            .zoomSource("shows-\(summary.show.feedURL)", in: zoom)
                    }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        Button("Unfollow", glyph: .close, role: .destructive) {
                            Task { await podcasts.setFollowed(summary.show, false) }
                        }
                    }
                }
            }
            .padding(.horizontal, theme.spacing.screenInset)
            .padding(.vertical, theme.spacing.lg)
        }
        .overlay {
            if shows.isEmpty {
                EmptyState("No Shows", glyph: .podcasts, message: "Shows you follow appear here.")
            }
        }
        .themedBackground()
        .navigationTitle("Shows")
        .task {
            do {
                for try await value in podcasts.observe(podcasts.database.followedShows()) { shows = value }
            } catch { Log.observationFailed(error) }
        }
    }

    /// The show's route, zooming out of its tile.
    private func zoomRoute(_ show: ShowRecord) -> ShowRoute {
        var route = ShowRoute(show)
        route.sourceID = "shows-\(show.feedURL)"
        return route
    }
}
