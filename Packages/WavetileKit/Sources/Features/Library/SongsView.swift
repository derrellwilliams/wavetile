import DesignSystem
import Library
import Persistence
import SwiftUI

/// Every song, A–Z. `List` keeps scrolling smooth on tens of thousands of rows (cell reuse).
struct SongsView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @State private var tracks: [TrackRecord] = []

    var body: some View {
        List(tracks) { track in
            TrackRow(
                title: track.title,
                subtitle: track.artistName,
                duration: track.durationMs.map { .milliseconds($0) },
                leading: .artwork(store.artwork(itemID: track.albumID, maxPixelWidth: 144))
            )
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .overlay {
            if tracks.isEmpty { LibraryEmptyState() }
        }
        .themedBackground()
        .navigationTitle("Songs")
        .task {
            do {
                for try await value in store.observe(store.database.allTracks()) { tracks = value }
            } catch {}
        }
        .enableInjection()
    }
}
