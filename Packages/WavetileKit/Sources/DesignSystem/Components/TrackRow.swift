import SwiftUI

/// A single track in album, playlist, and search lists.
public struct TrackRow: View {
    public enum Leading: Sendable {
        case number(Int?)
        case artwork(ArtworkSource)
    }

    @Environment(\.theme) private var theme
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
                Text(title)
                    .font(theme.typography.body)
                    .foregroundStyle(isPlaying ? theme.palette.accent : theme.palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(theme.typography.itemSubtitle)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: theme.spacing.sm)
            if isDownloaded {
                Glyph.downloads.image
                    .resizable()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(theme.palette.textSecondary)
                    .accessibilityLabel("Downloaded")
            }
            if let duration {
                Text(duration, format: .time(pattern: .minuteSecond))
                    .font(theme.typography.itemSubtitle.monospacedDigit())
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isPlaying ? .isSelected : [])
    }

    @ViewBuilder private var leadingView: some View {
        switch leading {
        case let .number(number):
            Group {
                if isPlaying {
                    Glyph.waveform.image
                        .pulsing(isPlaying)
                        .foregroundStyle(theme.palette.accent)
                } else {
                    Text(number.map(String.init) ?? "")
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .font(theme.typography.itemSubtitle.monospacedDigit())
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
        TrackRow(title: "Nude", subtitle: "Radiohead", duration: .seconds(255), leading: .artwork(.placeholder(seed: 2)))
    }
    .listStyle(.plain)
}
