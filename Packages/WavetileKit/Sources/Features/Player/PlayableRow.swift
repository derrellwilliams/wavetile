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
            albumImageTag: record.albumImageTag,
            duration: record.durationMs.map { .milliseconds($0) },
            normalizationGain: record.normalizationGain
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
            duration: track.duration,
            normalizationGain: track.normalizationGain
        )
    }
}

/// Makes a track row playable: tap plays the surrounding list from this row; long-press
/// offers Play Next / Add to Queue. `tracks` is built lazily on tap, so long lists stay cheap.
/// `onTap` replaces the default play (search plays the song's album);
/// the long-press menu is the same. `showsMore` adds a trailing ⋯ with that menu, so the
/// actions don't depend on discovering the long press; `moreLabel` names it for VoiceOver.
struct PlayableRow<Label: View>: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    @Environment(Connectivity.self) private var connectivity
    @Environment(LibraryActions.self) private var actions
    @Environment(LibraryStore.self) private var store
    @Environment(\.pushLibraryRoute) private var push
    let trackID: String
    let index: Int
    let tracks: () -> [QueuedTrack]
    /// This row's track alone, for Play Next / Add to Queue, so they don't build the whole list.
    var track: (() -> QueuedTrack?)?
    var onTap: (() -> Void)?
    /// Adds Play / Go to Album / Go to Artist to the long press, matching the ⋯ sheet.
    var menu: SongMenu?
    var showsMore = false
    var moreLabel = "More"
    @ViewBuilder let label: Label
    /// Haptic on the tap that starts playback, not on every track change (auto-advance included).
    @State private var taps = 0

    var body: some View {
        HStack(spacing: 0) {
            tapAction
                // Offline, only downloaded songs can play; dim the rest.
                .disabled(!isAvailable)
                .opacity(isAvailable ? 1 : 0.35)
                .contextMenu { menuItems }
            if showsMore {
                Menu { menuItems } label: {
                    Glyph.more.image
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(theme.palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel(moreLabel)
            }
        }
        .sensoryFeedback(.selection, trigger: taps)
    }

    private func thisTrack() -> QueuedTrack? {
        track?() ?? tracks()[safe: index]
    }

    @ViewBuilder private var menuItems: some View {
        if let menu {
            Button("Play", glyph: .play, action: menu.play)
            if let album = menu.album { Button("Go to Album", glyph: .album) { push(album) } }
            if let artist = menu.artist { Button("Go to Artist", glyph: .artist) { push(artist) } }
            Divider()
        }
        Button("Play Next", glyph: .playNext) {
            if let track = thisTrack() { player.playNext([track.requeued()]) }
        }
        Button("Add to Queue", glyph: .queue) {
            if let track = thisTrack() { player.addToQueue([track.requeued()]) }
        }
        Button("Start Radio", glyph: .radio) { actions.startRadio(from: trackID, store: store, player: player) }
        Divider()
        Button("Add to Playlist", glyph: .addToQueue) { actions.addToPlaylist([trackID]) }
        Button("Favorite", glyph: .favorite) {
            actions.favorite(trackID, store: store)
        }
    }

    private var tapAction: some View {
        Button {
            taps += 1
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
    func play(_ queue: [QueuedTrack], startAt index: Int = 0, shuffled: Bool = false, online: Bool, downloads: DownloadsStore) {
        var queue = queue
        var start = index
        if !online {
            let tapped = queue[safe: index]?.queueID
            queue = queue.filter { downloads.isDownloaded($0.trackID) }
            start = queue.firstIndex { $0.queueID == tapped } ?? 0
        }
        play(queue, startAt: start, shuffled: shuffled)
    }
}
