import DesignSystem
import JellyfinKit
import Library
import Persistence
import Playback
import Podcasts
import SwiftUI

/// Offline full-text search over the synced library. The search field itself is attached here
/// (scoped to this tab); `.tabViewSearchActivation` on the TabView makes the tab detach.
/// With podcasts on, an All | Music | Podcasts filter appears (All is the default). All shows
/// music plus followed podcasts from the device, and Apple Podcasts shows only when they match
/// what was typed. Privacy: with podcasts on, All and Podcasts send the typed text to Apple's
/// directory after typing pauses; Music never leaves the device, nor does anything with podcasts off.
struct SearchView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    @Namespace private var zoom
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    @Environment(Connectivity.self) private var connectivity
    @Environment(\.openNowPlaying) private var openNowPlaying
    @Environment(PodcastsStore.self) private var podcasts
    @Binding var text: String
    @Binding var scope: MediaKind
    @State private var results = LibraryDatabase.SearchResults()
    @State private var podcastResults = PodcastDatabase.SearchResults()
    /// Apple Podcasts shows for the All filter, already narrowed to ones named like the query.
    @State private var appleShows: [DirectoryShow] = []
    @State private var path = NavigationPath()
    /// The song whose ⋯ actions sheet is showing.
    @State private var actionsTrack: TrackRecord?
    @State private var recents = RecentSearches()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch podcasts.isEnabled ? scope : .music {
                case .podcasts: PodcastSearchResults(text: text)
                // With nothing typed, recent searches replace the empty state (Podcasts keeps its own).
                case .all where showsRecents, .music where showsRecents: recentSearches
                case .all: allResults
                case .music: musicResults
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if podcasts.isEnabled { MediaFilter(selection: $scope, options: [.all, .music, .podcasts]) }
            }
            .themedBackground()
            .navigationTitle("Search")
            .tabRootChrome()
            // Inside libraryDestinations, so the sheet gets the stack's push (Go to Album/Artist).
            .sheet(item: $actionsTrack, onDismiss: actions.presentPending) { track in
                SongActionsSheet(
                    track: track,
                    artwork: store.artwork(itemID: track.albumID, maxPixelWidth: 144),
                    menu: store.songMenu(for: track, source: "search") { play(track) }
                )
            }
            .libraryDestinations(zoom: zoom) { path.append($0) }
            .podcastDestinations(zoom: zoom) { path.append($0) }
        }
        // Scoped to this tab's stack so the field doesn't leak into other tabs' navigation bars.
        .searchable(text: $text, prompt: prompt)
        .onSubmit(of: .search) { recents.add(text) }
        // Opening a result from the search root keeps the query.
        .onChange(of: path.count) { old, new in
            if old == 0, new > 0 { recents.add(text) }
        }
        .task(id: text) {
            // Debounce typing; FTS queries are fast but there's no need to run one per keystroke.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            results = (try? store.database.search(text)) ?? .init()
            podcastResults = podcasts.isEnabled ? ((try? podcasts.database.search(text)) ?? .init()) : .init()
        }
        .task(id: "\(scope)|\(text)") { await searchApple() }
        .enableInjection()
    }

    /// All filter only: Apple's shows that match the query, minus ones already followed.
    /// The last results stay up while typing, until new ones replace them, so the section doesn't
    /// vanish and reappear on every keystroke.
    private func searchApple() async {
        let query = trimmedText
        guard podcasts.isEnabled, scope == .all, query.count >= 2 else {
            appleShows = []
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
            if trimmedText.isEmpty {
                EmptyState("Search Everything", glyph: .search, message: "Find artists, albums, songs, and the podcasts you follow.")
            }
        }
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespaces) }

    private var showsRecents: Bool { trimmedText.isEmpty && !recents.queries.isEmpty }

    private var recentSearches: some View {
        List {
            Section {
                ForEach(recents.queries, id: \.self) { query in
                    Button { text = query } label: {
                        Label(query, glyph: .history)
                            .labelStyle(.tintedIcon)
                            .font(theme.typography.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
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
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
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
                        HStack(spacing: theme.spacing.xs) {
                            PlayableRow(
                                trackID: track.id, index: index,
                                tracks: { results.tracks.map(QueuedTrack.init) },
                                onTap: { play(track) },
                                menu: store.songMenu(for: track, source: "search") { play(track) }
                            ) {
                                TrackRow(
                                    title: track.title,
                                    subtitle: "\(track.artistName) · \(track.albumTitle)",
                                    duration: track.durationMs.map { .milliseconds($0) },
                                    leading: .artwork(store.artwork(itemID: track.albumID, maxPixelWidth: 144)),
                                    isPlaying: player.current?.trackID == track.id,
                                    isDownloaded: downloads.isDownloaded(track.id)
                                )
                            }
                            GlyphButton("More for \(track.title)", glyph: .more, size: 20) { actionsTrack = track }
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.palette.accent)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
    }

    /// Plays the song within its album (so playback continues through the record, not the
    /// search results) and opens Now Playing.
    private func play(_ track: TrackRecord) {
        var queue = [QueuedTrack(track)]
        if let albumID = track.albumID, let albumTracks = try? store.database.tracks(albumID: albumID), !albumTracks.isEmpty {
            queue = albumTracks.map(QueuedTrack.init)
        }
        // Offline, queue only what's on the device (same rule as tapping any row).
        if !connectivity.isOnline { queue = queue.filter { downloads.isDownloaded($0.trackID) } }
        guard let start = queue.firstIndex(where: { $0.trackID == track.id }) else { return }
        recents.add(text)
        player.play(queue, startAt: start)
        openNowPlaying()
    }

    @ViewBuilder private var emptyState: some View {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyState("Search Your Library", glyph: .search, message: "Find artists, albums, and songs, even offline.")
        } else if results.isEmpty {
            EmptyState("No Results", glyph: .search, message: "Nothing in your library matches “\(text)”.")
        }
    }
}
