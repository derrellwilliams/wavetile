import SwiftUI

/// Album artwork with title and subtitle, used in shelves and grids.
public struct AlbumTile: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: String
    private let subtitle: String
    private let artwork: ArtworkSource

    public init(title: String, subtitle: String, artwork: ArtworkSource) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            ArtworkView(artwork)
                .shadow(color: .black.opacity(theme.artwork.shadowOpacity), radius: theme.artwork.shadowRadius, y: 4)
                .padding(.bottom, theme.spacing.xxs)
            Text(title)
                .font(theme.typography.itemTitle)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityIdentifier("albumTile")
            Text(subtitle)
                .font(theme.typography.itemSubtitle)
                .foregroundStyle(theme.palette.textSecondary)
        }
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        .accessibilityElement(children: .combine)
        // Lets UI tests recognize tiles (single-line titles truncate by design at normal sizes).
        .accessibilityIdentifier("albumTile")
    }
}

#Preview {
    AlbumTile(title: "In Rainbows", subtitle: "Radiohead", artwork: .placeholder(seed: 3))
        .frame(width: 160)
        .padding()
}
