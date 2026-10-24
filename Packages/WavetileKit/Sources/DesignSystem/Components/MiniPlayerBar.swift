import SwiftUI

/// Contents of the tab bar bottom accessory. The system supplies the Liquid Glass capsule;
/// this view adapts to the `.inline` placement when the tab bar minimizes on scroll.
public struct MiniPlayerBar: View {
    @Environment(\.theme) private var theme
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    private let title: String
    private let subtitle: String
    private let artwork: ArtworkSource
    private let isPlaying: Bool
    private let onPlayPause: () -> Void
    private let onNext: () -> Void

    public init(
        title: String,
        subtitle: String,
        artwork: ArtworkSource,
        isPlaying: Bool,
        onPlayPause: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.onPlayPause = onPlayPause
        self.onNext = onNext
    }

    public var body: some View {
        HStack(spacing: theme.spacing.md) {
            ArtworkView(artwork)
                .frame(width: theme.artwork.miniPlayerThumbnail)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(theme.typography.itemTitle)
                if placement != .inline {
                    Text(subtitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Button(isPlaying ? "Pause" : "Play", glyph: isPlaying ? .pause : .play, action: onPlayPause)
                .contentTransition(.opacity)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
            if placement != .inline {
                Button("Next", glyph: .next, action: onNext)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .tint(theme.palette.accent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing: \(title), \(subtitle)")
        .padding(.horizontal, theme.spacing.md)
        .sensoryFeedback(.selection, trigger: isPlaying)
    }
}

#Preview {
    @Previewable @State var isPlaying = true
    TabView {
        Tab { Text("Home") } label: { Label("Home", glyph: .home) }
        Tab { Text("Library") } label: { Label("Library", glyph: .library) }
    }
    .tabViewBottomAccessory {
        MiniPlayerBar(
            title: "Weird Fishes/Arpeggi",
            subtitle: "Radiohead",
            artwork: .placeholder(seed: 5),
            isPlaying: isPlaying,
            onPlayPause: { isPlaying.toggle() },
            onNext: {}
        )
    }
}
