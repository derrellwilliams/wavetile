import DesignSystem
import JellyfinKit
import Library
import Persistence
import Playback
import SwiftUI

/// Offline full-text search over the synced library. The search field itself is attached here
/// (scoped to this tab); `.tabViewSearchActivation` on the TabView makes the tab detach.
/// With podcasts on, a Music | Podcasts filter switches to `PodcastSearchResults`.
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
    @State private var path = NavigationPath()
    /// The song whose ⋯ actions sheet is showing.
    @State private var actionsTrack: TrackRecord?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if podcasts.isEnabled && scope == .podcasts {
                    PodcastSearchResults(text: text)
                } else {
                    musicResults
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if podcasts.isEnabled { MediaFilter(selection: $scope) }
            }
            .themedBackground()
            .navigationTitle("Search")
            .tabRootChrome()
            .libraryDestinations(zoom: zoom) { path.append($0) }
            .podcastDestinations { path.append($0) }
            .sheet(item: $actionsTrack, onDismiss: actions.presentPending) { track in
                SongActionsSheet(
                    track: track,
                    artwork: store.artwork(itemID: track.albumID, maxPixelWidth: 144),
                    menu: store.songMenu(for: track, source: "search") { play(track) }
                )
            }
        }
        // Scoped to this tab's stack so the field doesn't leak into other tabs' navigation bars.
        .searchable(text: $text, prompt: podcasts.isEnabled && scope == .podcasts ? "Shows and episodes" : "Artists, albums, songs")
        .task(id: text) {
            // Debounce typing; FTS queries are fast but there's no need to run one per keystroke.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            results = (try? store.database.search(text)) ?? .init()
        }
        .enableInjection()
    }

    private var musicResults: some View {
            List {
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
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .overlay { emptyState }
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
