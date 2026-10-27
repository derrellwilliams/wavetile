import DesignSystem
import Persistence
import SwiftUI

/// Top of Home while there's little play history: library size, Shuffle All and Genres.
struct WelcomeCard: View {
    @Environment(\.theme) private var theme
    let stats: LibraryStats
    let onShuffle: () -> Void
    let onGenres: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text("Welcome to Wavetile")
                    .font(theme.typography.title)
                    .foregroundStyle(theme.palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .font(theme.typography.itemSubtitle)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            HStack(spacing: theme.spacing.md) {
                PrimaryButton("Shuffle All", action: onShuffle)
                Button(action: onGenres) {
                    Label("Genres", glyph: .genre)
                        .labelStyle(.tintedIcon)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(theme.spacing.lg)
        .background(theme.palette.surface, in: .rect(cornerRadius: theme.radius.card))
        .padding(.horizontal, theme.spacing.screenInset)
    }

    private var summary: String {
        [
            count(stats.albums, "album"),
            count(stats.artists, "artist"),
            count(stats.tracks, "song"),
        ].joined(separator: " · ")
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n.formatted()) \(noun)\(n == 1 ? "" : "s")"
    }
}

/// Playlist tile for Home shelves.
struct PlaylistLink: View {
    @Environment(LibraryStore.self) private var store
    let playlist: PlaylistRecord

    var body: some View {
        NavigationLink(value: LibraryRoute.playlist(playlist)) {
            AlbumTile(
                title: playlist.name,
                subtitle: "\(playlist.trackCount) song\(playlist.trackCount == 1 ? "" : "s")",
                artwork: store.artwork(itemID: playlist.id, tag: playlist.imageTag, maxPixelWidth: 480)
            )
        }
        .buttonStyle(.pressable)
    }
}

/// One artist and their albums, at the bottom of Home. A new artist is picked each launch
/// and on pull to refresh.
struct ArtistSpotlightShelf: View {
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    let spotlight: HomeModel.Spotlight
    let onOpenArtist: () -> Void

    var body: some View {
        ShelfSection(items: spotlight.albums) {
            Button(action: onOpenArtist) {
                HStack(spacing: theme.spacing.md) {
                    ArtworkView(store.artwork(itemID: spotlight.artistID, tag: spotlight.imageTag, maxPixelWidth: 192))
                        .frame(width: 56, height: 56)
                        .clipShape(.circle)
                    VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                        Text("Artist Spotlight")
                            .font(theme.typography.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(theme.palette.accent)
                        Text(spotlight.name)
                            .font(theme.typography.sectionHeader)
                            .foregroundStyle(theme.palette.textPrimary)
                            .lineLimit(1)
                    }
                    Glyph.chevron.image
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
        } tile: { album in
            AlbumLink(album: album, context: "spotlight")
        }
    }
}
