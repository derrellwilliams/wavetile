import DesignSystem
import SwiftUI
import WidgetKit
import WidgetShared

struct RecentsEntry: TimelineEntry {
    let date: Date
    let albums: [RecentAlbumSnapshot]
}

struct RecentsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentsEntry {
        RecentsEntry(date: .now, albums: (0 ..< 8).map { RecentAlbumSnapshot(id: "\($0)", title: "Album", artist: "Artist", artworkFile: nil) })
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentsEntry) -> Void) {
        let albums = WidgetStore.loadRecents()
        completion(albums.isEmpty ? placeholder(in: context) : RecentsEntry(date: .now, albums: albums))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentsEntry>) -> Void) {
        completion(Timeline(entries: [RecentsEntry(date: .now, albums: WidgetStore.loadRecents())], policy: .never))
    }
}

struct RecentlyPlayedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.recentlyPlayed, provider: RecentsProvider()) { entry in
            RecentsView(entry: entry)
                .containerBackground(Theme.dark.palette.background, for: .widget)
        }
        .configurationDisplayName("Recently Played")
        .description("Jump back into albums you've been playing.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct RecentsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentsEntry

    var body: some View {
        let count = family == .systemLarge ? 8 : 4
        let albums = Array(entry.albums.prefix(count))
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently Played")
                .font(Theme.dark.typography.itemTitle)
                .foregroundStyle(Theme.dark.palette.textPrimary)
            if albums.isEmpty {
                Spacer()
                Text("Play some music to see it here.")
                    .font(Theme.dark.typography.caption)
                    .foregroundStyle(Theme.dark.palette.textSecondary)
                Spacer()
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(albums) { album in
                        Link(destination: WidgetLink.album(album.id)) {
                            WidgetArtwork(file: album.artworkFile)
                        }
                        .accessibilityLabel("\(album.title) by \(album.artist)")
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview("Recently Played", as: .systemLarge) {
    RecentlyPlayedWidget()
} timeline: {
    RecentsEntry(date: .now, albums: (0 ..< 8).map { RecentAlbumSnapshot(id: "\($0)", title: "Album \($0)", artist: "Artist", artworkFile: nil) })
}
