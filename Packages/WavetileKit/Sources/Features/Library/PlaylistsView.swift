import DesignSystem
import Library
import Persistence
import SwiftUI

struct PlaylistsView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @State private var playlists: [PlaylistRecord] = []

    var body: some View {
        List(playlists) { playlist in
            NavigationLink(value: LibraryRoute.playlist(playlist)) {
                HStack(spacing: theme.spacing.md) {
                    ArtworkView(store.artwork(itemID: playlist.id, tag: playlist.imageTag, maxPixelWidth: 192))
                        .frame(width: 56)
                    VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                        Text(playlist.name)
                            .font(theme.typography.body)
                            .foregroundStyle(theme.palette.textPrimary)
                        Text("\(playlist.trackCount) songs")
                            .font(theme.typography.itemSubtitle)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    .lineLimit(1)
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .overlay {
            if playlists.isEmpty { LibraryEmptyState() }
        }
        .themedBackground()
        .navigationTitle("Playlists")
        .task {
            do {
                for try await value in store.observe(store.database.playlists()) { playlists = value }
            } catch {}
        }
        .enableInjection()
    }
}

/// Playlist page: full-bleed artwork, name and stats, then tracks.
struct PlaylistDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    let playlist: PlaylistRecord
    @State private var tracks: [TrackRecord] = []

    private var artwork: ArtworkSource {
        store.artwork(itemID: playlist.id, tag: playlist.imageTag, maxPixelWidth: 1320)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.xl) {
                VStack(spacing: theme.spacing.md) {
                    ArtworkHero(artwork: artwork)
                    VStack(spacing: theme.spacing.xs) {
                        Text(playlist.name)
                            .font(theme.typography.title)
                            .foregroundStyle(theme.palette.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("\(playlist.trackCount) songs · \(Duration.milliseconds(playlist.durationMs).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    .padding(.horizontal, theme.spacing.screenInset)
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                        TrackRow(
                            title: track.title,
                            subtitle: track.artistName,
                            duration: track.durationMs.map { .milliseconds($0) },
                            leading: .artwork(store.artwork(itemID: track.albumID, maxPixelWidth: 144))
                        )
                        .padding(.horizontal, theme.spacing.screenInset)
                        .padding(.vertical, theme.spacing.sm)
                    }
                }
            }
            .padding(.bottom, theme.spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            tracks = (try? store.database.tracks(playlistID: playlist.id)) ?? []
        }
        .enableInjection()
    }
}
