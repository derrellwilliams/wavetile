import DesignSystem
import Foundation
import JellyfinKit
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
    private let library: LibraryClient?

    init(album: AlbumSummary, library: LibraryClient?) {
        self.album = album
        self.library = library
    }

    /// Preview initializer with fixed tracks and no network.
    init(previewAlbum album: AlbumSummary, tracks: [TrackSummary]) {
        self.album = album
        self.tracks = tracks
        self.library = nil
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

    func load() async {
        guard let library, tracks.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            tracks = try await library.albumTracks(albumID: album.id)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load tracks."
        }
    }

    /// Hero art is ~300pt wide; 3x scale.
    var artwork: ArtworkSource {
        guard let library else { return Fixtures.artwork(for: album) }
        return .url(library.imageURL(itemID: album.id, tag: album.imageTag, maxPixelWidth: 960))
    }
}
