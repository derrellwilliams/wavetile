import DesignSystem
import Podcasts
import SwiftUI

/// A podcast shelf on Home (when podcasts are on): Continue Listening or Up Next in Podcasts.
/// Home owns the data and only places a shelf when it has episodes, so Home stays music-only
/// until there's something to show.
struct PodcastHomeShelf: View {
    @Environment(\.theme) private var theme
    let title: String
    let items: [EpisodeItem]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            Text(title)
                .font(theme.typography.sectionHeader)
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.horizontal, theme.spacing.screenInset)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: theme.spacing.lg) {
                    ForEach(items) { item in
                        EpisodeCard(item: item)
                            .frame(width: theme.artwork.shelfTileWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, theme.spacing.screenInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
        .transition(.opacity)
    }
}
