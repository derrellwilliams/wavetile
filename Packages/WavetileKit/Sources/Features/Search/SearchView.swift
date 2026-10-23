import DesignSystem
import Library
import Persistence
import Playback
import SwiftUI

/// Offline full-text search over the synced library. The search field itself is attached here
/// (scoped to this tab); `.tabViewSearchActivation` on the TabView makes the tab detach.
struct SearchView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Namespace private var zoom
    @Environment(AudioPlayer.self) private var player
    @Binding var text: String
    @State private var results = LibraryDatabase.SearchResults()

    var body: some View {
        NavigationStack {
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
                            PlayableRow(index: index, tracks: { results.tracks.map(QueuedTrack.init) }) {
                                TrackRow(
                                    title: track.title,
                                    subtitle: "\(track.artistName) · \(track.albumTitle)",
                                    duration: track.durationMs.map { .milliseconds($0) },
                                    leading: .artwork(store.artwork(itemID: track.albumID, maxPixelWidth: 144)),
                                    isPlaying: player.current?.trackID == track.id
                                )
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .overlay { emptyState }
            .themedBackground()
            .reportsTabRoot()
            .navigationTitle("Search")
            .libraryDestinations(zoom: zoom)
        }
        // Scoped to this tab's stack so the field doesn't leak into other tabs' navigation bars.
        .searchable(text: $text, prompt: "Artists, albums, songs")
        .task(id: text) {
            // Debounce typing; FTS queries are fast but there's no need to run one per keystroke.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            results = (try? store.database.search(text)) ?? .init()
        }
        .enableInjection()
    }

    @ViewBuilder private var emptyState: some View {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyState("Search Your Library", glyph: .search, message: "Find artists, albums, and songs, even offline.")
        } else if results.isEmpty {
            EmptyState("No Results", glyph: .search, message: "Nothing in your library matches “\(text)”.")
        }
    }
}
