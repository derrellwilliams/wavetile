import DesignSystem
import Library
import Persistence
import SwiftUI

/// A–Z artist list with a section index (iOS 26 list index).
struct ArtistsView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @State private var sections: [(letter: String, artists: [ArtistRecord])] = []

    var body: some View {
        List {
            ForEach(sections, id: \.letter) { section in
                Section {
                    ForEach(section.artists) { artist in
                        NavigationLink(value: LibraryRoute.artist(id: artist.id, name: artist.name)) {
                            HStack(spacing: theme.spacing.md) {
                                ArtworkView(store.artwork(itemID: artist.id, tag: artist.imageTag, maxPixelWidth: 144))
                                    .frame(width: theme.artwork.rowThumbnail)
                                    .clipShape(.circle)
                                Text(artist.name)
                                    .font(theme.typography.body)
                                    .foregroundStyle(theme.palette.textPrimary)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text(section.letter)
                        .font(theme.typography.caption.weight(.semibold))
                }
                .sectionIndexLabel(section.letter)
            }
        }
        .listStyle(.plain)
        .listSectionIndexVisibility(.visible)
        .overlay {
            if sections.isEmpty { LibraryEmptyState() }
        }
        .themedBackground()
        .navigationTitle("Artists")
        .task {
            do {
                for try await artists in store.observe(store.database.artists()) {
                    sections = Self.group(artists)
                }
            } catch { Log.observationFailed(error) }
        }
        .enableInjection()
    }

    /// Artists arrive sorted by sort key, so grouping preserves order; "#" sorts first.
    private static func group(_ artists: [ArtistRecord]) -> [(letter: String, artists: [ArtistRecord])] {
        var result: [(letter: String, artists: [ArtistRecord])] = []
        for artist in artists {
            let letter = SortKey.section(artist.sortName)
            if result.last?.letter == letter {
                result[result.count - 1].artists.append(artist)
            } else if let index = result.firstIndex(where: { $0.letter == letter }) {
                result[index].artists.append(artist)
            } else {
                result.append((letter, [artist]))
            }
        }
        return result.sorted { ($0.letter == "#" ? "" : $0.letter) < ($1.letter == "#" ? "" : $1.letter) }
    }
}
