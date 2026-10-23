import DesignSystem
import Foundation
import JellyfinKit
import Library
import Observation
import PreviewSupport

/// Navigation value for an album. `sourceID` ties the zoom transition to the exact tile tapped,
/// since the same album can appear in several shelves.
struct AlbumRoute: Hashable {
    let album: AlbumSummary
    let sourceID: String
}

@Observable
final class AlbumDetailModel {
    let album: AlbumSummary
    private(set) var tracks: [TrackSummary] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let store: LibraryStore?

    init(album: AlbumSummary, store: LibraryStore?) {
        self.album = album
        self.store = store
        // Synchronous local read: tracks are on screen in the first frame when the library is synced.
        if let store, let local = try? store.database.tracks(albumID: album.id), !local.isEmpty {
            tracks = local.map(\.summary)
        }
    }

    /// Preview initializer with fixed tracks and no network.
    init(previewAlbum album: AlbumSummary, tracks: [TrackSummary]) {
        self.album = album
        self.tracks = tracks
        self.store = nil
    }

    var totalDuration: Duration {
        tracks.compactMap(\.duration).reduce(.zero, +)
    }

    /// Show disc headers only for multi-disc albums.
    var discs: [(number: Int?, tracks: [TrackSummary])] {
        let grouped = Dictionary(grouping: tracks, by: \.discNumber)
        guard grouped.count > 1 else { return [(nil, tracks)] }
        return grouped.keys.sorted { ($0 ?? 0) < ($1 ?? 0) }.map { ($0, grouped[$0] ?? []) }
    }

    /// Hero art spans the screen width (~440pt × 3x).
    var artwork: ArtworkSource {
        guard let store else { return Fixtures.artwork(for: album) }
        return store.artwork(itemID: album.id, tag: album.imageTag, maxPixelWidth: 1320)
    }

    /// Falls back to the server when the album isn't in the local library yet (first sync running).
    func load() async {
        guard let store, tracks.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            tracks = try await store.api.albumTracks(albumID: album.id)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load tracks."
        }
    }
}
