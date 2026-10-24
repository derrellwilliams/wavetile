import DesignSystem
import Library
import Persistence
import Playback
import SwiftUI

/// Every song, A–Z. `List` keeps scrolling smooth on tens of thousands of rows (cell reuse).
struct SongsView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    @State private var tracks: [TrackRecord] = []
    /// Row index by track ID, rebuilt only when the list changes (not on every render).
    @State private var indexByID: [String: Int] = [:]

    var body: some View {
        List(tracks) { track in
            PlayableRow(trackID: track.id, index: indexByID[track.id] ?? 0, tracks: { tracks.map(QueuedTrack.init) }) {
                TrackRow(
                    title: track.title,
                    subtitle: track.artistName,
                    duration: track.durationMs.map { .milliseconds($0) },
                    leading: .artwork(store.artwork(itemID: track.albumID, maxPixelWidth: 144)),
                    isPlaying: player.current?.trackID == track.id,
                    isDownloaded: downloads.isDownloaded(track.id)
                )
            }
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
                for try await value in store.observe(store.database.allTracks()) {
                    tracks = value
                    indexByID = Dictionary(value.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
                }
            } catch {}
        }
        .enableInjection()
    }
}
