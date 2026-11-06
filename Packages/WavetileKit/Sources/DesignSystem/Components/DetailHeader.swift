import SwiftUI

/// The title block under a detail page's hero art (album, playlist, show, episode), so every
/// page uses the same type: 36 title, 18 subtitle, 17 mono metadata.
/// Compact titles (episodes) are 22: they run long.
public struct DetailHeader<Subtitle: View>: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let metadata: String?
    private let compact: Bool
    private let subtitle: Subtitle

    /// `compact` uses the 22pt title, for titles that run long (podcast episodes).
    public init(_ title: String, metadata: String? = nil, compact: Bool = false, @ViewBuilder subtitle: () -> Subtitle) {
        self.title = title
        self.metadata = metadata
        self.compact = compact
        self.subtitle = subtitle()
    }

    public var body: some View {
        // Flush left on the screen margin, like the rest of the grid.
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(title)
                .font(compact ? theme.typography.title : theme.typography.largeTitle)
                // Only 36pt titles are tightened.
                .tracking(compact ? 0 : theme.typography.displayTracking)
                .lineSpacing(theme.typography.titleLeading)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            subtitle
            if let metadata, !metadata.isEmpty {
                Text(metadata)
                    // Body size, like the artist bio, so year and length read at a glance.
                    .font(theme.typography.mono(.body))
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.screenInset)
        // The same break before the buttons as between the artist page's buttons and bio.
        .padding(.bottom, theme.spacing.sm)
    }
}

extension DetailHeader where Subtitle == EmptyView {
    public init(_ title: String, metadata: String? = nil) {
        self.init(title, metadata: metadata) { EmptyView() }
    }
}

/// A detail page's secondary name (artist, publisher, show), one step under the title. Wrap it in a link to make it tappable.
public struct DetailSubtitle: View {
    @Environment(\.theme) private var theme
    private let text: String
    private let compact: Bool

    /// `compact` uses 18pt for show names beneath episode titles.
    public init(_ text: String, compact: Bool = false) {
        self.text = text
        self.compact = compact
    }

    public var body: some View {
        Text(text)
            .font(compact ? theme.typography.sectionHeader : theme.typography.lead)
            .foregroundStyle(theme.palette.textPrimary)
    }
}

extension View {
    /// Chrome for a scrolling detail page that starts with `ArtworkHero`: the art runs under
    /// the navigation bar with no bar background or edge blur.
    public func detailPageChrome() -> some View {
        scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .scrollEdgeEffectHidden(true, for: .top)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .themedBackground()
            .navigationBarTitleDisplayMode(.inline)
    }
}
