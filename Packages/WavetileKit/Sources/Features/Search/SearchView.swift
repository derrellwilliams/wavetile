import DesignSystem
import JellyfinKit
import Library
import Persistence
import Playback
import Podcasts
import SwiftUI

/// Offline full-text search over the synced library. The search field itself is attached here
/// (scoped to this tab); `.tabViewSearchActivation` on the TabView makes the tab detach.
/// With podcasts on, an All | Music | Podcasts filter sits under the title (All is the default). All shows
/// music plus followed podcasts from the device, and Apple Podcasts shows only when they match
/// what was typed. Privacy: with podcasts on, All and Podcasts send the typed text to Apple's
/// directory after typing pauses; Music never leaves the device, nor does anything with podcasts off.
/// Recent searches are the field's suggestions while it's empty.
struct SearchView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Namespace private var zoom
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    @Environment(PodcastsStore.self) private var podcasts
    @Binding var text: String
    @Binding var scope: MediaKind
    @State private var results = LibraryDatabase.SearchResults()
    /// The text `results` were found for, so "No Results" waits for the search to finish.
    @State private var searchedText = ""
    /// The query Apple's directory has answered (or was skipped) for, under the All scope.
    @State private var appleSearchedText = ""
    @State private var podcastResults = PodcastDatabase.SearchResults()
    /// Apple Podcasts shows for the All filter, already narrowed to ones named like the query.
    @State private var appleShows: [DirectoryShow] = []
    let reselects: Int
    @State private var path = NavigationPath()
    /// Tapping the tab again at its root scrolls back to the top.
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var recents = RecentSearches()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch podcasts.isEnabled ? scope : .music {
                case .podcasts: PodcastSearchResults(text: text)
                case .all: allResults
                case .music: musicResults
                }
            }
            .scrollPosition($scrollPosition)
            // The title, then the filter (in place of the system scope bar), pinned above the results.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    title
                    OfflineNotice(gap: theme.spacing.md)
                    if podcasts.isEnabled {
                        MediaFilter(selection: $scope, options: MediaKind.allCases)
                    }
                }
                // Opaque, so results don't scroll visibly through the translucent capsule.
                .background(theme.palette.background)
            }
            .themedBackground()
            .onTabReselect(reselects, path: $path) { scrollToTop() }
            // The offline notice (and dimming) slide in and out.
            .animatesConnectivity()
            // iOS hides the bar's large title while the field is active, and this tab activates it
            // on selection, so the title is drawn above the filter instead. The bar's title stays
            // for VoiceOver and Back, but isn't shown.
            .navigationTitle("Search")
            .toolbarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .tabRootChrome()
            .libraryDestinations(zoom: zoom) { path.append($0) }
            .podcastDestinations(zoom: zoom) { path.append($0) }
        }
        // Scoped to this tab's stack so the field doesn't leak into other tabs' navigation bars.
        .searchable(text: $text, prompt: prompt)
        // Keeps the bar (title, profile, wave) while searching, like every other tab; iOS hides it by default.
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .searchSuggestions { recentSuggestions }
        .onSubmit(of: .search) { recents.add(text) }
        // Opening a result from the search root keeps the query.
        .onChange(of: path.count) { old, new in
            if old == 0, new > 0 { recents.add(text) }
        }
        .task(id: text) {
            // Debounce typing; FTS queries are fast but there's no need to run one per keystroke.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let found = (try? await store.database.search(text)) ?? .init()
            let podcastFound = podcasts.isEnabled ? ((try? await podcasts.database.search(text)) ?? .init()) : .init()
            // A slow search for earlier text must not land on top of the newer one's results.
            guard !Task.isCancelled else { return }
            results = found
            podcastResults = podcastFound
            searchedText = text
        }
        .task(id: "\(scope)|\(text)") { await searchApple() }
        .enableInjection()
    }

    private func scrollToTop() {
        withAnimation(theme.motion.smooth) { scrollPosition.scrollTo(edge: .top) }
    }

    /// All filter only: Apple's shows that match the query, minus ones already followed.
    /// The last results stay up while typing, until new ones replace them, so the section doesn't
    /// vanish and reappear on every keystroke.
    private func searchApple() async {
        let query = trimmedText
        guard podcasts.isEnabled, scope == .all, query.count >= 2 else {
            appleShows = []
            appleSearchedText = query
            return
        }
        // Debounce: Apple allows about 20 searches a minute per device.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        let shows = (try? await podcasts.directory.search(query)) ?? []
        guard !Task.isCancelled else { return }
        let followed = Set(podcastResults.shows.map(\.feedURL))
        let relevant = shows.filter { show in show.matches(query) && !(show.feedURL.map(followed.contains) ?? false) }
        withAnimation(theme.motion.smooth) { appleShows = Array(relevant.prefix(5)) }
        appleSearchedText = query
    }

    /// Styled and placed like the other tabs' large titles: 36pt in the 75pt row under the bar,
    /// sitting a little above its middle as theirs do.
    private var title: some View {
        Text("Search")
            .font(theme.typography.largeTitle)
            .tracking(theme.typography.displayTracking)
            .foregroundStyle(theme.palette.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
            .padding(.bottom, 10)
            .padding(.horizontal, theme.spacing.screenInset)
    }

    private var prompt: String {
        switch podcasts.isEnabled ? scope : .music {
        case .all: "Music and podcasts"
        case .music: "Artists, albums, songs"
        case .podcasts: "Shows and episodes"
        }
    }

    /// Music and followed podcasts together, local only. Apple's directory is one tap away.
    private var allResults: some View {
        List {
            musicSections
            PodcastLocalSections(results: podcastResults, part: .shows)
            if !appleShows.isEmpty {
                Section("Apple Podcasts") {
                    ForEach(appleShows) { DirectoryShowRow(show: $0) }
                }
            }
            PodcastLocalSections(results: podcastResults, part: .episodes)
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            // Nothing before typing: the title and field say what this is.
            if !trimmedText.isEmpty, searchedText == text, appleSearchedText == trimmedText,
                      results.isEmpty, podcastResults.isEmpty, appleShows.isEmpty {
                EmptyState("No Results", message: "Nothing in your library, your podcasts, or Apple Podcasts matches “\(text)”.")
            }
        }
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespaces) }

    /// Shown while the field is active and empty; tapping one fills in and runs the search.
    /// Podcasts keeps its own empty screen.
    @ViewBuilder private var recentSuggestions: some View {
        if trimmedText.isEmpty, !recents.queries.isEmpty, !(podcasts.isEnabled && scope == .podcasts) {
            Section {
                ForEach(recents.queries, id: \.self) { query in
                    Label(query, glyph: .history)
                        .labelStyle(.tintedIcon)
                        .font(theme.typography.body)
                        .searchCompletion(query)
                        .swipeActions {
                            Button("Remove", glyph: .trash, role: .destructive) { recents.remove(query) }
                        }
                }
            } header: {
                HStack {
                    Text("Recent Searches")
                    Spacer()
                    Button("Clear") { withAnimation(theme.motion.smooth) { recents.clear() } }
                        .font(theme.typography.body)
                        .foregroundStyle(theme.palette.accent)
                }
            }
        }
    }

    private var musicResults: some View {
        List { musicSections }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .overlay { emptyState }
    }

    @ViewBuilder private var musicSections: some View {
            if !results.artists.isEmpty {
                Section("Artists") {
                    ForEach(results.artists) { artist in
                        NavigationLink(value: LibraryRoute.artist(id: artist.id, name: artist.name)) {
                            HStack(spacing: theme.spacing.md) {
                                ArtworkView(store.artwork(itemID: artist.id, tag: artist.imageTag, maxPixelWidth: 144))
                                    .frame(width: theme.artwork.rowThumbnail)
                                    .clipShape(.circle)
                                Text(artist.name).font(theme.typography.body)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            if !results.albums.isEmpty {
                Section("Albums") {
                    ForEach(results.albums) { album in
                        NavigationLink(value: LibraryRoute.album(AlbumRoute(album: album.summary, sourceID: "search-\(album.id)"))) {
                            TrackRow(
                                title: album.title,
                                subtitle: album.artistName,
                                leading: .artwork(store.artwork(itemID: album.id, tag: album.imageTag, maxPixelWidth: 144))
                            )
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            if !results.tracks.isEmpty {
                Section("Songs") {
                    ForEach(Array(results.tracks.enumerated()), id: \.element.id) { index, track in
                        PlayableRow(
                            trackID: track.id, index: index,
                            tracks: { results.tracks.map(QueuedTrack.init) },
                            onTap: { play(track) },
                            menu: store.songMenu(for: track, source: "search") { play(track) },
                            showsMore: true, moreLabel: "More for \(track.title)"
                        ) {
                            TrackRow(
                                title: track.title,
                                subtitle: "\(track.artistName) · \(track.albumTitle)",
                                duration: track.durationMs.map { .milliseconds($0) },
                                leading: .artwork(store.artwork(itemID: track.albumID, tag: track.albumImageTag, maxPixelWidth: 144)),
                                isPlaying: player.current?.trackID == track.id,
                                isDownloaded: downloads.isDownloaded(track.id)
                            )
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
    }

    /// Plays the song within its album (so playback continues through the record, not the
    /// search results). Search stays up, like Apple Music; the mini player shows the song.
    private func play(_ track: TrackRecord) {
        var queue = [QueuedTrack(track)]
        if let albumID = track.albumID, let albumTracks = try? store.database.tracks(albumID: albumID), !albumTracks.isEmpty {
            queue = albumTracks.map(QueuedTrack.init)
        }
        guard let start = queue.firstIndex(where: { $0.trackID == track.id }) else { return }
        recents.add(text)
        player.play(queue, startAt: start)
    }

    @ViewBuilder private var emptyState: some View {
        // Nothing before typing: the title and field say what this is.
        if !text.trimmingCharacters(in: .whitespaces).isEmpty, searchedText == text, results.isEmpty {
            EmptyState("No Results", message: "Nothing in your library matches “\(text)”.")
        }
    }
}
