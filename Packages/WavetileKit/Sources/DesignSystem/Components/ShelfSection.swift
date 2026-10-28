import SwiftUI

/// A titled, horizontally scrolling shelf (Home "Recently Played", "Most Played", etc.).
/// Snaps to tiles and keeps the system scroll margins.
public struct ShelfSection<Item: Identifiable, Tile: View, Header: View>: View {
    @Environment(\.theme) private var theme
    private let items: [Item]
    private let header: Header
    private let tile: (Item) -> Tile

    /// A shelf under a custom header (inset to the screen margins by the shelf).
    public init(items: [Item], @ViewBuilder header: () -> Header, @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.items = items
        self.header = header()
        self.tile = tile
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            header
                .padding(.horizontal, theme.spacing.screenInset)

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

public extension ShelfSection where Header == ShelfTitle {
    /// A shelf under a plain title.
    init(_ title: String, items: [Item], @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.init(items: items, header: { ShelfTitle(title) }, tile: tile)
    }
}

/// A shelf's section header.
public struct ShelfTitle: View {
    @Environment(\.theme) private var theme
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(theme.typography.sectionHeader)
            .foregroundStyle(theme.palette.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    struct Sample: Identifiable { let id: Int }
    return ShelfSection("Recently Played", items: (0..<8).map(Sample.init)) { item in
        AlbumTile(title: "Album \(item.id)", subtitle: "Artist", artwork: .placeholder(seed: item.id))
    }
}
