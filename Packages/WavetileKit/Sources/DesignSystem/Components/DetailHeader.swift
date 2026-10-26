import SwiftUI

/// The title block under a detail page's hero art (album, playlist, show, episode), so every
/// page uses the same type: Stack Sans Notch title, text-face subtitle, footnote metadata.
public struct DetailHeader<Subtitle: View>: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let metadata: String?
    private let compact: Bool
    private let subtitle: Subtitle

    /// `compact` uses the smaller title size, for titles that run long (podcast episodes).
    public init(_ title: String, metadata: String? = nil, compact: Bool = false, @ViewBuilder subtitle: () -> Subtitle) {
        self.title = title
        self.metadata = metadata
        self.compact = compact
        self.subtitle = subtitle()
    }

    public var body: some View {
        VStack(spacing: theme.spacing.xs) {
            Text(title)
                .font(compact ? theme.typography.title : theme.typography.largeTitle)
                .tracking(theme.typography.displayTracking)
                .foregroundStyle(theme.palette.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            subtitle
            if let metadata, !metadata.isEmpty {
                Text(metadata)
                    // One point up from caption (12pt), still scaling with Dynamic Type.
                    .font(BrandFont.font(.footnote))
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, theme.spacing.screenInset)
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
            .font(BrandFont.font(.title3, weight: .medium))
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
