import SwiftUI

/// A titled, horizontally scrolling shelf (Home "Recently Played", "Most Played", etc.).
/// Snaps to tiles and keeps the system scroll margins.
public struct ShelfSection<Item: Identifiable, Tile: View>: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let items: [Item]
    private let tile: (Item) -> Tile

    public init(_ title: String, items: [Item], @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.title = title
        self.items = items
        self.tile = tile
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            Text(title)
                .font(theme.typography.sectionHeader)
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.horizontal, theme.spacing.screenInset)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: theme.spacing.lg) {
                    ForEach(items) { item in
                        tile(item)
                            .frame(width: theme.artwork.shelfTileWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, theme.spacing.screenInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

#Preview {
    struct Sample: Identifiable { let id: Int }
    return ShelfSection("Recently Played", items: (0..<8).map(Sample.init)) { item in
        AlbumTile(title: "Album \(item.id)", subtitle: "Artist", artwork: .placeholder(seed: item.id))
    }
}
