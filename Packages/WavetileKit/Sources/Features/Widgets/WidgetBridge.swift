import DesignSystem
import Foundation
import JellyfinKit
import Nuke
import Playback
import UIKit
import WidgetKit
import WidgetShared

/// Publishes app state to the widgets (via the app group) and receives widget button presses.
@MainActor
final class WidgetBridge {
    private let player: AudioPlayer
    private let library: LibraryStore
    private var lastSnapshot: NowPlayingSnapshot?
    private var artworkTask: Task<Void, Never>?

    init(player: AudioPlayer, library: LibraryStore) {
        self.player = player
        self.library = library
        PlaybackCommandCenter.shared.handler = { [weak player] command in
            switch command {
            case .togglePlayPause: player?.togglePlayPause()
            case .next: player?.next()
            }
        }
    }

    /// Call when the current track or play state changes.
    func playerChanged() {
        guard let track = player.current else {
            if lastSnapshot != nil {
                lastSnapshot = nil
                WidgetStore.saveNowPlaying(nil)
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nowPlaying)
            }
            return
        }
        let trackChanged = lastSnapshot?.title != track.title || lastSnapshot?.album != track.albumTitle
        var snapshot = NowPlayingSnapshot(
            title: track.title,
            artist: track.artist,
            album: track.albumTitle,
            albumID: track.albumID,
            isPlaying: player.isPlaying,
            artworkFile: trackChanged ? nil : lastSnapshot?.artworkFile
        )
        // Write immediately (title/state), then again once artwork is cached.
        publish(snapshot)
        guard trackChanged || snapshot.artworkFile == nil, let albumID = track.albumID else { return }
        artworkTask?.cancel()
        artworkTask = Task {
            guard let file = await saveArtwork(itemID: albumID, tag: track.albumImageTag), !Task.isCancelled,
                  player.current?.queueID == track.queueID
            else { return }
            snapshot.artworkFile = file
            snapshot.isPlaying = player.isPlaying
            publish(snapshot)
        }
    }

    /// Call when Home's Recently Played shelf loads.
    func recentsChanged(_ albums: [AlbumSummary]) {
        let top = Array(albums.prefix(8))
        Task {
            var snapshots: [RecentAlbumSnapshot] = []
            for album in top {
                let file = await saveArtwork(itemID: album.id, tag: album.imageTag)
                snapshots.append(RecentAlbumSnapshot(id: album.id, title: album.title, artist: album.artist, artworkFile: file))
            }
            guard snapshots != WidgetStore.loadRecents() else { return }
            WidgetStore.saveRecents(snapshots)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.recentlyPlayed)
        }
    }

    static func clear() {
        WidgetStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func publish(_ snapshot: NowPlayingSnapshot) {
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        WidgetStore.saveNowPlaying(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nowPlaying)
    }

    /// Fetches (usually from the disk cache) and stores a 300px JPEG; widgets can't load URLs.
    private func saveArtwork(itemID: String, tag: String?) async -> String? {
        guard let url = library.api.imageURL(itemID: itemID, tag: tag, maxPixelWidth: 480),
              let image = try? await ImagePipeline.shared.image(for: url)
        else { return nil }
        let data = await Task.detached(priority: .utility) { Self.thumbnailJPEG(image) }.value
        return data.flatMap { WidgetStore.saveArtwork($0, id: itemID) }
    }

    private nonisolated static func thumbnailJPEG(_ image: UIImage) -> Data? {
        let side: CGFloat = 300
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }
}
