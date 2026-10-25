import DesignSystem
import JellyfinKit
import Persistence
import Playback
import SwiftUI

extension QueuedTrack {
    init(_ record: TrackRecord) {
        self.init(
            trackID: record.id,
            title: record.title,
            artist: record.artistName,
            albumTitle: record.albumTitle,
            albumID: record.albumID,
            duration: record.durationMs.map { .milliseconds($0) }
        )
    }

    init(_ track: TrackSummary, album: AlbumSummary) {
        self.init(
            trackID: track.id,
            title: track.title,
            artist: track.artist,
            albumTitle: album.title,
            albumID: album.id,
            albumImageTag: album.imageTag,
            duration: track.duration
        )
    }
}

/// Makes a track row playable: tap plays the surrounding list from this row; long-press
/// offers Play Next / Add to Queue. `tracks` is built lazily on tap, so long lists stay cheap.
/// `onTap` replaces the default play (search plays the song's album and opens Now Playing);
/// the long-press menu is the same.
struct PlayableRow<Label: View>: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    @Environment(Connectivity.self) private var connectivity
    @Environment(LibraryActions.self) private var actions
    @Environment(LibraryStore.self) private var store
    @Environment(\.pushLibraryRoute) private var push
    let trackID: String
    let index: Int
    let tracks: () -> [QueuedTrack]
    var onTap: (() -> Void)?
    /// Adds Play / Go to Album / Go to Artist to the long press, matching the ⋯ sheet.
    var menu: SongMenu?
    @ViewBuilder let label: Label

    var body: some View {
        tapAction
            // Offline, only downloaded songs can play; dim the rest.
            .disabled(!isAvailable)
            .opacity(isAvailable ? 1 : 0.35)
            .contextMenu {
                if let menu {
                    Button("Play", glyph: .play, action: menu.play)
                    if let album = menu.album { Button("Go to Album", glyph: .album) { push(album) } }
                    if let artist = menu.artist { Button("Go to Artist", glyph: .artist) { push(artist) } }
                    Divider()
                }
                Button("Play Next", glyph: .playNext) {
                    if let track = tracks()[safe: index] { player.playNext([track.requeued()]) }
                }
                Button("Add to Queue", glyph: .queue) {
                    if let track = tracks()[safe: index] { player.addToQueue([track.requeued()]) }
                }
                Divider()
                Button("Add to Playlist", glyph: .addToQueue) { actions.addToPlaylist([trackID]) }
                Button("Favorite", glyph: .favorite) {
                    Task { try? await store.editor.setFavorite(itemID: trackID, true) }
                }
            }
            .sensoryFeedback(.selection, trigger: player.current?.trackID)
    }

    private var tapAction: some View {
        Button {
            if let onTap { return onTap() }
            player.play(tracks(), startAt: index, online: connectivity.isOnline, downloads: downloads)
        } label: {
            label.contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var isAvailable: Bool {
        connectivity.isOnline || downloads.isDownloaded(trackID)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension AudioPlayer {
    /// Plays `queue` from `index`. Offline, queues only what's on the device so playback
    /// doesn't hit dead tracks.
    func play(_ queue: [QueuedTrack], startAt index: Int, online: Bool, downloads: DownloadsStore) {
        var queue = queue
        var start = index
        if !online {
            let tapped = queue[safe: index]?.queueID
            queue = queue.filter { downloads.isDownloaded($0.trackID) }
            start = queue.firstIndex { $0.queueID == tapped } ?? 0
        }
        play(queue, startAt: start)
    }
}
