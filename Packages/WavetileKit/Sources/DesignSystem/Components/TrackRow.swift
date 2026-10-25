import SwiftUI

/// A single track in album, playlist, and search lists.
public struct TrackRow: View {
    public enum Leading: Sendable {
        case number(Int?)
        case artwork(ArtworkSource)
    }

    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isAudioPlaying) private var isAudioPlaying
    private let title: String
    private let subtitle: String?
    private let duration: Duration?
    private let leading: Leading
    private let isPlaying: Bool
    private let isDownloaded: Bool

    public init(
        title: String, subtitle: String? = nil, duration: Duration? = nil, leading: Leading,
        isPlaying: Bool = false, isDownloaded: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.duration = duration
        self.leading = leading
        self.isPlaying = isPlaying
        self.isDownloaded = isDownloaded
    }

    public var body: some View {
        HStack(spacing: theme.spacing.md) {
            leadingView
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                // Long titles wrap to a second line rather than being cut off.
                Text(title)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(isAccessibilitySize ? nil : 2)
                if let subtitle {
                    Text(subtitle)
                        .font(theme.typography.itemSubtitle)
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(isAccessibilitySize ? nil : 1)
                }
                // At accessibility sizes the duration moves under the title instead of squeezing it.
                if isAccessibilitySize, let duration {
                    Text(duration, format: .time(pattern: .minuteSecond))
                        .font(theme.typography.itemSubtitle.monospacedDigit())
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            Spacer(minLength: theme.spacing.sm)
            if isDownloaded {
                Glyph.downloads.image
                    .resizable()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            if !isAccessibilitySize, let duration {
                Text(duration, format: .time(pattern: .minuteSecond))
                    .font(theme.typography.itemSubtitle.monospacedDigit())
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trackRow")
        .accessibilityValue([isPlaying ? "Now playing" : nil, isDownloaded ? "Downloaded" : nil].compactMap(\.self).joined(separator: ", "))
        .accessibilityAddTraits(isPlaying ? .isSelected : [])
    }

    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    @ViewBuilder private var leadingView: some View {
        switch leading {
        case let .number(number):
            Group {
                if isPlaying {
                    WaveformIndicator(isAnimating: isAudioPlaying)
                        .foregroundStyle(theme.palette.accent)
                } else {
                    Text(number.map(String.init) ?? "")
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .font(theme.typography.itemSubtitle.monospacedDigit())
            .id(isPlaying)
            .transition(.iconSwap)
            .animation(theme.motion.snappy, value: isPlaying)
            .frame(minWidth: 24)
        case let .artwork(source):
            ArtworkView(source)
                .frame(width: theme.artwork.rowThumbnail)
        }
    }
}

#Preview {
    List {
        TrackRow(title: "15 Step", duration: .seconds(237), leading: .number(1))
        TrackRow(title: "Bodysnatchers", duration: .seconds(242), leading: .number(2), isPlaying: true)
            .environment(\.isAudioPlaying, true)
        TrackRow(title: "Nude", subtitle: "Radiohead", duration: .seconds(255), leading: .artwork(.placeholder(seed: 2)))
    }
    .listStyle(.plain)
}
