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
    /// Every song plus its row index by ID, built off the main actor when the list changes.
    @State private var list = TrackList()
    @Environment(Connectivity.self) private var connectivity

    var body: some View {
        List(tracks) { track in
            PlayableRow(
                trackID: track.id, index: indexByID[track.id] ?? 0,
                tracks: { tracks.map(QueuedTrack.init) },
                track: { QueuedTrack(track) },
                menu: menu(for: track),
                showsMore: true, moreLabel: "More for \(track.title)"
            ) {
                TrackRow(
                    title: track.title,
                    subtitle: track.artistName,
                    duration: track.durationMs.map { .milliseconds($0) },
                    leading: .artwork(store.artwork(itemID: track.albumID, tag: track.albumImageTag, maxPixelWidth: 144)),
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
                for try await value in store.observe(store.database.allTracks()) { list = value }
            } catch { Log.observationFailed(error) }
        }
        .enableInjection()
    }

    private var tracks: [TrackRecord] { list.tracks }
    private var indexByID: [String: Int] { list.indexByID }

    private func menu(for track: TrackRecord) -> SongMenu {
        store.songMenu(for: track, source: "songs") {
            player.play(tracks.map(QueuedTrack.init), startAt: indexByID[track.id] ?? 0,
                        online: connectivity.isOnline, downloads: downloads)
        }
    }
}
