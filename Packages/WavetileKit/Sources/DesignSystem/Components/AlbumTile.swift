import SwiftUI

/// Album artwork with title and subtitle, used in shelves and grids.
public struct AlbumTile: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: String
    private let subtitle: String
    private let artwork: ArtworkSource
    private let subtitleIsMetadata: Bool
    private let isDownloaded: Bool

    /// `subtitle` is a name (artist, author) in Inter; `subtitleIsMetadata` sets it in mono
    /// instead, for counts. `isDownloaded` puts the download mark on the artwork: something in it
    /// plays offline.
    public init(title: String, subtitle: String, artwork: ArtworkSource, subtitleIsMetadata: Bool = false, isDownloaded: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.subtitleIsMetadata = subtitleIsMetadata
        self.isDownloaded = isDownloaded
    }

    public var body: some View {
        // Title and artist sit tight together; the artwork keeps its 6pt gap above them.
        VStack(alignment: .leading, spacing: 0) {
            ArtworkView(artwork)
                // Shadow from a plain shape behind the art, not the clipped image itself: a known
                // path is cheap to blur, where an image's shadow needs an offscreen pass per tile.
                .background {
                    RoundedRectangle(cornerRadius: theme.radius.artwork, style: .continuous)
                        .fill(theme.palette.background)
                        .shadow(color: .black.opacity(theme.artwork.shadowOpacity), radius: theme.artwork.shadowRadius, y: 4)
                }
                .downloadMarked(isDownloaded)
                .padding(.bottom, theme.spacing.xs + theme.spacing.xxs)
            Text(title)
                .font(theme.typography.itemTitle)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityIdentifier("albumTile")
            Text(subtitle)
                .font(subtitleIsMetadata ? theme.typography.itemMetadata : theme.typography.itemSubtitle)
                .foregroundStyle(theme.palette.textSecondary)
                .accessibilityIdentifier("albumTile")
        }
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDownloaded ? "Downloaded" : "")
        // Lets UI tests recognize tiles (single-line titles truncate by design at normal sizes).
        .accessibilityIdentifier("albumTile")
    }
}

/// Marks artwork whose album, playlist or collection plays offline: the download icon on a dark
/// grey disc, shown online and offline alike so what plays without a connection is never a guess.
public struct DownloadMark: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        Glyph.downloads.image
            .resizable()
            .frame(width: theme.artwork.downloadMarkIcon, height: theme.artwork.downloadMarkIcon)
            .foregroundStyle(theme.palette.downloadMarkIcon)
            .frame(width: theme.artwork.downloadMark, height: theme.artwork.downloadMark)
            .background(theme.palette.downloadMark, in: .circle)
            .accessibilityHidden(true)
    }
}

public extension View {
    /// Puts the download mark in the top-right corner of this artwork when `isDownloaded`.
    func downloadMarked(_ isDownloaded: Bool) -> some View {
        modifier(DownloadMarked(isDownloaded: isDownloaded))
    }
}

private struct DownloadMarked: ViewModifier {
    @Environment(\.theme) private var theme
    let isDownloaded: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if isDownloaded { DownloadMark().padding(theme.spacing.xs + theme.spacing.xxs) }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        AlbumTile(title: "In Rainbows", subtitle: "Radiohead", artwork: .placeholder(seed: 3))
        AlbumTile(title: "Kid A", subtitle: "Radiohead", artwork: .placeholder(seed: 4), isDownloaded: true)
    }
    .frame(width: 336)
    .padding()
}
