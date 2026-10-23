import DesignSystem
import Library
import Persistence
import Playback
import SwiftUI

struct FavoritesView: View {
    enum Kind: String, CaseIterable { case songs = "Songs", albums = "Albums", artists = "Artists" }

    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    @State private var kind: Kind = .songs
    @State private var tracks: [TrackRecord] = []
    @State private var albums: [AlbumRecord] = []
    @State private var artists: [ArtistRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.lg) {
                Picker("Show", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, theme.spacing.screenInset)

                switch kind {
                case .songs: songs
                case .albums: albumGrid
                case .artists: artistList
                }
            }
            .padding(.vertical, theme.spacing.lg)
        }
        .overlay {
            if isEmpty {
                EmptyState("No Favorites", glyph: .favorite, message: "Tap the heart on songs, albums, and artists to find them here.")
            }
        }
        .themedBackground()
        .navigationTitle("Favorites")
        .task { await observe() }
        .enableInjection()
    }

    private var isEmpty: Bool {
        switch kind {
        case .songs: tracks.isEmpty
        case .albums: albums.isEmpty
        case .artists: artists.isEmpty
        }
    }

    private var songs: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                PlayableRow(trackID: track.id, index: index, tracks: { tracks.map(QueuedTrack.init) }) {
                    TrackRow(
                        title: track.title,
                        subtitle: track.artistName,
                        duration: track.durationMs.map { .milliseconds($0) },
                        leading: .artwork(store.artwork(itemID: track.albumID, maxPixelWidth: 144)),
                        isPlaying: player.current?.trackID == track.id,
                        isDownloaded: downloads.isDownloaded(track.id)
                    )
                    .padding(.horizontal, theme.spacing.screenInset)
                    .padding(.vertical, theme.spacing.sm)
                }
            }
        }
    }

    private var albumGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: theme.artwork.shelfTileWidth - 8), spacing: theme.spacing.lg)],
            alignment: .leading,
            spacing: theme.spacing.xl
        ) {
            ForEach(albums) { album in
                AlbumLink(album: album.summary, context: "favorites")
            }
        }
        .padding(.horizontal, theme.spacing.screenInset)
    }

    private var artistList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(artists) { artist in
                NavigationLink(value: LibraryRoute.artist(id: artist.id, name: artist.name)) {
                    HStack(spacing: theme.spacing.md) {
                        ArtworkView(store.artwork(itemID: artist.id, tag: artist.imageTag, maxPixelWidth: 144))
                            .frame(width: theme.artwork.rowThumbnail)
                            .clipShape(.circle)
                        Text(artist.name)
                            .font(theme.typography.body)
                            .foregroundStyle(theme.palette.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, theme.spacing.screenInset)
                    .padding(.vertical, theme.spacing.sm)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func observe() async {
        async let t: Void = observeTracks()
        async let a: Void = observeAlbums()
        async let r: Void = observeArtists()
        _ = await (t, a, r)
    }

    private func observeTracks() async {
        do { for try await value in store.observe(store.database.favoriteTracks()) { tracks = value } } catch {}
    }

    private func observeAlbums() async {
        do { for try await value in store.observe(store.database.favoriteAlbums()) { albums = value } } catch {}
    }

    private func observeArtists() async {
        do { for try await value in store.observe(store.database.favoriteArtists()) { artists = value } } catch {}
    }
}
