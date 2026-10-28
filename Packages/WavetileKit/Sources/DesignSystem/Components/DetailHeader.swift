import SwiftUI

/// The title block under a detail page's hero art (album, playlist, show, episode), so every
/// page uses the same type: Stack Sans Notch title, text-face subtitle, body-size metadata.
/// Compact titles (episodes) use the text face instead: they run long, and read more easily in it.
public struct DetailHeader<Subtitle: View>: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let metadata: String?
    private let compact: Bool
    private let subtitle: Subtitle

    /// `compact` uses the smaller, text-face title, for titles that run long (podcast episodes).
    public init(_ title: String, metadata: String? = nil, compact: Bool = false, @ViewBuilder subtitle: () -> Subtitle) {
        self.title = title
        self.metadata = metadata
        self.compact = compact
        self.subtitle = subtitle()
    }

    public var body: some View {
        VStack(spacing: theme.spacing.xs) {
            Text(title)
                .font(compact ? theme.typography.compactTitle : theme.typography.largeTitle)
                // Only the display face is tightened; the text face keeps its own spacing.
                .tracking(compact ? 0 : theme.typography.displayTracking)
                // The text face has a shallower descent than the display face (5pt vs 10pt), so it
                // gets the difference back as padding to sit as far from the subtitle as album titles do.
                .padding(.bottom, compact ? theme.spacing.xs : 0)
                .foregroundStyle(theme.palette.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            subtitle
            if let metadata, !metadata.isEmpty {
                Text(metadata)
                    // Body size, like the artist bio, so year and length read at a glance.
                    .font(theme.typography.body)
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
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

/// A detail page's secondary name (artist, publisher, show) in the text face: it's metadata,
/// not a title, so it never uses Stack Sans Notch. Wrap it in a link to make it tappable.
public struct DetailSubtitle: View {
    @Environment(\.theme) private var theme
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(theme.typography.lead.weight(.medium))
            .foregroundStyle(theme.palette.textPrimary)
            .multilineTextAlignment(.center)
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
