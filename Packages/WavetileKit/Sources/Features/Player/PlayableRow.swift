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
struct PlayableRow<Label: View>: View {
    @Environment(AudioPlayer.self) private var player
    let index: Int
    let tracks: () -> [QueuedTrack]
    @ViewBuilder let label: Label

    var body: some View {
        Button {
            player.play(tracks(), startAt: index)
        } label: {
            label.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play Next", glyph: .playNext) {
                if let track = tracks()[safe: index] { player.playNext([track.requeued()]) }
            }
            Button("Add to Queue", glyph: .addToQueue) {
                if let track = tracks()[safe: index] { player.addToQueue([track.requeued()]) }
            }
        }
        .sensoryFeedback(.selection, trigger: player.current?.trackID)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
