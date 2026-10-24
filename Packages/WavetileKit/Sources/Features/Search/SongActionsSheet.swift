import DesignSystem
import Persistence
import SwiftUI

/// The ⋯ sheet for a song in search results: play it, or jump to its album or artist.
/// Album and artist are nil (hidden) when the song isn't linked to a synced album.
struct SongActionsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let track: TrackRecord
    let artwork: ArtworkSource
    let onPlay: () -> Void
    let onAlbum: (() -> Void)?
    let onArtist: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            HStack(spacing: theme.spacing.md) {
                ArtworkView(artwork)
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    Text(track.title)
                        .font(theme.typography.itemTitle)
                        .foregroundStyle(theme.palette.textPrimary)
                    Text("\(track.artistName) · \(track.albumTitle)")
                        .font(theme.typography.itemSubtitle)
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .lineLimit(2)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 0) {
                action("Play", glyph: .play, perform: onPlay)
                if let onAlbum { action("Go to Album", glyph: .album, perform: onAlbum) }
                if let onArtist { action("Go to Artist", glyph: .artist, perform: onArtist) }
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing.screenInset)
        .padding(.top, theme.spacing.sm)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// Dismisses first so navigation and Now Playing happen on the screen underneath.
    private func action(_ title: String, glyph: Glyph, perform: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            perform()
        } label: {
            Label(title, glyph: glyph)
                .labelStyle(.tintedIcon)
                .font(theme.typography.body)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
