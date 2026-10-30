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
        // A launch never resumes playback, so a snapshot still saying "playing" is left over
        // from a crash or the app being killed; show it paused rather than a dead Pause button.
        if var saved = WidgetStore.loadNowPlaying() {
            saved.isPlaying = false
            publish(saved)
        }
        PlaybackCommandCenter.shared.handler = { [weak player] command in
            switch command {
            case .togglePlayPause: player?.togglePlayPause()
            case .next:
                // Episodes skip ahead instead of jumping to the next episode.
                if let player, player.current?.isEpisode == true {
                    player.skip(by: player.skipForwardInterval)
                } else {
                    player?.next()
                }
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
        // The next song on the same album keeps its art: no placeholder flash, no re-encode.
        let sameArt = !trackChanged || (!track.isEpisode && track.albumID != nil && lastSnapshot?.albumID == track.albumID)
        var snapshot = NowPlayingSnapshot(
            title: track.title,
            artist: track.artist,
            album: track.albumTitle,
            albumID: track.albumID,
            isPlaying: player.isPlaying,
            artworkFile: sameArt ? lastSnapshot?.artworkFile : nil
        )
        // Write immediately (title/state), then again once artwork is cached.
        publish(snapshot)
        guard snapshot.artworkFile == nil else { return }
        let source: (url: URL, id: String)?
        if let art = track.podcast?.artworkURL {
            // Episode IDs are stable hex, so they make safe, reusable file names.
            source = (art, "podcast\(track.trackID)")
        } else if let albumID = track.albumID, let url = library.api.imageURL(itemID: albumID, tag: track.albumImageTag, maxPixelWidth: 480) {
            source = (url, albumID)
        } else {
            source = nil
        }
        guard let source else { return }
        artworkTask?.cancel()
        artworkTask = Task {
            guard let file = await saveArtwork(url: source.url, id: source.id), !Task.isCancelled,
                  player.current?.queueID == track.queueID
            else { return }
            snapshot.artworkFile = file
            snapshot.isPlaying = player.isPlaying
            publish(snapshot)
            Self.pruneArtwork()
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
            Self.pruneArtwork()
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
        guard let url = library.api.imageURL(itemID: itemID, tag: tag, maxPixelWidth: 480) else { return nil }
        return await saveArtwork(url: url, id: itemID)
    }

    private func saveArtwork(url: URL, id: String) async -> String? {
        guard let image = try? await ImagePipeline.shared.image(for: url) else { return nil }
        let data = await Self.thumbnailJPEG(image)
        return data.flatMap { WidgetStore.saveArtwork($0, id: id) }
    }

    /// Deletes artwork files no snapshot refers to, so the folder doesn't grow with every album played.
    /// Here, not in WidgetShared: it reads file dates (a required-reason API) and only the app
    /// needs it, so the widget extension's binary stays free of it.
    private static func pruneArtwork() {
        guard let directory = AppGroup.containerURL?.appending(path: "Artwork", directoryHint: .isDirectory),
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        else { return }
        let kept = Set([WidgetStore.loadNowPlaying()?.artworkFile].compactMap(\.self) + WidgetStore.loadRecents().compactMap(\.artworkFile))
        // Recent files are spared: one may be written but not yet in a saved snapshot.
        let cutoff = Date().addingTimeInterval(-600)
        for file in files where !kept.contains(file) {
            let url = directory.appending(path: file)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Resizing and JPEG encoding run off the main actor.
    @concurrent private static func thumbnailJPEG(_ image: UIImage) async -> Data? {
        let side: CGFloat = 300
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }
}
