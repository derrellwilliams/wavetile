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
    @Environment(LibraryActions.self) private var actions
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    /// Every song plus its row index by ID, built off the main actor when the list changes.
    @State private var list = TrackList()
    @Environment(Connectivity.self) private var connectivity
    /// The song whose ⋯ actions sheet is showing.
    @State private var actionsTrack: TrackRecord?

    var body: some View {
        List(tracks) { track in
            HStack(spacing: theme.spacing.xs) {
                PlayableRow(
                    trackID: track.id, index: indexByID[track.id] ?? 0,
                    tracks: { tracks.map(QueuedTrack.init) },
                    track: { QueuedTrack(track) },
                    menu: menu(for: track)
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
                GlyphButton("More for \(track.title)", glyph: .more, size: 20) { actionsTrack = track }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.palette.accent)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .overlay {
            if tracks.isEmpty { LibraryEmptyState() }
        }
        .themedBackground()
        .navigationTitle("Songs")
        .sheet(item: $actionsTrack, onDismiss: actions.presentPending) { track in
            SongActionsSheet(track: track, artwork: store.artwork(itemID: track.albumID, tag: track.albumImageTag, maxPixelWidth: 144), menu: menu(for: track))
        }
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
