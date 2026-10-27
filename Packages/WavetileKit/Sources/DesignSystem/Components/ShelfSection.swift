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
    /// A shelf under a plain title; with `onTitleTap`, the title gets a chevron and opens more.
    init(_ title: String, items: [Item], onTitleTap: (() -> Void)? = nil, @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.init(items: items, header: { ShelfTitle(title, action: onTitleTap) }, tile: tile)
    }
}

/// A shelf's section header, optionally a button with a trailing chevron.
public struct ShelfTitle: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let action: (() -> Void)?

    public init(_ title: String, action: (() -> Void)? = nil) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) {
                HStack(spacing: theme.spacing.xs) {
                    label
                    Glyph.chevron.image
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
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
