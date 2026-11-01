import AppIntents
import DesignSystem
import SwiftUI
import WidgetKit
import WidgetShared

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snapshot: NowPlayingSnapshot(title: "Song Title", artist: "Artist", album: "Album", albumID: nil, isPlaying: true, artworkFile: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(NowPlayingEntry(date: .now, snapshot: WidgetStore.loadNowPlaying() ?? placeholder(in: context).snapshot))
    }

    /// The app reloads this timeline whenever the track or play state changes, so one entry suffices.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        completion(Timeline(entries: [NowPlayingEntry(date: .now, snapshot: WidgetStore.loadNowPlaying())], policy: .never))
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nowPlaying, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
                .containerBackground(Theme.dark.palette.background, for: .widget)
                .widgetURL(WidgetLink.nowPlaying)
        }
        .configurationDisplayName("Now Playing")
        .description("What's playing, with play/pause and skip.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryRectangular: rectangular(snapshot)
            case .systemMedium: medium(snapshot)
            default: small(snapshot)
            }
        } else {
            VStack(spacing: 6) {
                Glyph.waveform.image.foregroundStyle(Theme.dark.palette.textPrimary)
                Text("Nothing playing")
                    .font(BrandFont.font(.caption))
                    .foregroundStyle(Theme.dark.palette.textSecondary)
            }
        }
    }

    private func small(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                WidgetArtwork(file: snapshot.artworkFile)
                    .frame(width: 64, height: 64)
                Spacer()
                PlayPauseButton(isPlaying: snapshot.isPlaying)
            }
            Spacer(minLength: 0)
            titles(snapshot)
        }
    }

    private func medium(_ snapshot: NowPlayingSnapshot) -> some View {
        HStack(spacing: 14) {
            WidgetArtwork(file: snapshot.artworkFile)
            VStack(alignment: .leading, spacing: 8) {
                titles(snapshot)
                Spacer(minLength: 0)
                HStack(spacing: 18) {
                    PlayPauseButton(isPlaying: snapshot.isPlaying)
                    Button(intent: NextTrackIntent()) {
                        Glyph.next.image.resizable().frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.dark.palette.textPrimary)
                    .accessibilityLabel("Next")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func rectangular(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snapshot.title).font(BrandFont.font(.headline)).widgetAccentable()
            Text(snapshot.artist).font(BrandFont.font(.caption))
        }
        .lineLimit(1)
    }

    private func titles(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.title)
                .font(BrandFont.font(.subheadline))
                .foregroundStyle(Theme.dark.palette.textPrimary)
            Text(snapshot.artist)
                .font(BrandFont.font(.caption))
                .foregroundStyle(Theme.dark.palette.textSecondary)
        }
        .lineLimit(1)
    }
}

private struct PlayPauseButton: View {
    let isPlaying: Bool

    var body: some View {
        Button(intent: TogglePlaybackIntent()) {
            (isPlaying ? Glyph.pause : Glyph.play).image
                .resizable()
                .frame(width: 18, height: 18)
                .foregroundStyle(Theme.dark.palette.background)
                .frame(width: 36, height: 36)
                .background(Theme.dark.palette.textPrimary, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

#Preview("Now Playing", as: .systemMedium) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: .now, snapshot: NowPlayingSnapshot(title: "Weird Fishes/Arpeggi", artist: "Radiohead", album: "In Rainbows", albumID: nil, isPlaying: true, artworkFile: nil))
    NowPlayingEntry(date: .now, snapshot: NowPlayingSnapshot(title: "Weird Fishes/Arpeggi", artist: "Radiohead", album: "In Rainbows", albumID: nil, isPlaying: false, artworkFile: nil))
}

#Preview("Now Playing Small", as: .systemSmall) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: .now, snapshot: NowPlayingSnapshot(title: "Nude", artist: "Radiohead", album: "In Rainbows", albumID: nil, isPlaying: true, artworkFile: nil))
    NowPlayingEntry(date: .now, snapshot: nil)
}
