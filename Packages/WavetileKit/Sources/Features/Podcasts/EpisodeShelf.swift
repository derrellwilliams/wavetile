import DesignSystem
import Podcasts
import SwiftUI

/// A horizontal row of episode cards: Latest Podcast Episodes on Home; Continue Listening and
/// Latest Episodes on the Podcasts tab. The screen owns the data and only places a shelf when
/// it has episodes.
struct EpisodeShelf: View {
    @Environment(\.theme) private var theme
    let title: String
    let items: [EpisodeItem]
    var showsStatus = true

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
                        EpisodeCard(item: item, context: title, showsStatus: showsStatus)
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
