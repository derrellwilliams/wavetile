import DesignSystem
import Playback
import SwiftUI

/// Now Playing + Up Next. Drag to reorder, swipe to remove, tap to jump.
struct QueueView: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryStore.self) private var store
    @Environment(PodcastsStore.self) private var podcasts

    var body: some View {
        NavigationStack {
            List {
                if let current = player.current {
                    Section("Now Playing") {
                        row(current, isPlaying: true)
                    }
                }
                Section {
                    ForEach(player.queue.upNext) { track in
                        Button { player.jump(to: track.queueID) } label: { row(track, isPlaying: false) }
                            .buttonStyle(.plain)
                    }
                    .onMove {
                        player.moveUpNext(fromOffsets: $0, toOffset: $1)
                        podcasts.syncQueueOrder()
                    }
                    .onDelete { offsets in
                        let upcoming = Array(player.queue.upNext)
                        for track in offsets.map({ upcoming[$0] }) {
                            player.remove(track.queueID)
                            // Episodes also leave the saved podcast Up Next.
                            if track.isEpisode { podcasts.removeFromUpNext(track.trackID) }
                        }
                    }
                } header: {
                    Text("Up Next")
                } footer: {
                    if player.queue.upNext.isEmpty {
                        Text(player.current?.isEpisode == true ? "Nothing queued. Long-press an episode to add it." : "Nothing queued. Long-press a song to add it.")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ track: QueuedTrack, isPlaying: Bool) -> some View {
        TrackRow(
            title: track.title,
            subtitle: track.isEpisode ? track.albumTitle : track.artist,
            duration: track.duration,
            leading: .artwork(store.artwork(for: track, maxPixelWidth: 144)),
            isPlaying: isPlaying
        )
        .listRowBackground(Color.clear)
    }
}
