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
    private(set) var tracks: [TrackSummary] = [] {
        didSet { discs = Self.discs(tracks) }
    }
    /// The track list laid out by disc, worked out when `tracks` changes rather than per render
    /// (a box set is hundreds of rows, and the page redraws on every track change).
    private(set) var discs: [Disc] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// The album artist, from the synced library; nil if the album isn't synced yet.
    private(set) var artistID: String?
    private let store: LibraryStore?

    init(album: AlbumSummary, store: LibraryStore?) {
        self.album = album
        self.store = store
        // Synchronous local read: tracks are on screen in the first frame when the library is synced.
        if let store, let local = try? store.database.tracks(albumID: album.id), !local.isEmpty {
            tracks = local.map(\.summary)
            discs = Self.discs(tracks)
        }
        artistID = (try? store?.database.album(id: album.id))?.artistID
    }

    /// Preview initializer with fixed tracks and no network.
    init(previewAlbum album: AlbumSummary, tracks: [TrackSummary]) {
        self.album = album
        self.tracks = tracks
        self.store = nil
        discs = Self.discs(tracks)
    }

    var totalDuration: Duration {
        tracks.compactMap(\.duration).reduce(.zero, +)
    }

    struct Disc {
        /// Nil for single-disc albums, which show no disc header.
        let number: Int?
        let rows: [Row]
    }

    struct Row {
        let track: TrackSummary
        /// Position in the whole album, for playing from this row.
        let index: Int
        /// The tagged track number, else the position on its disc (untagged files sort by filename).
        let number: Int?
    }

    private static func discs(_ tracks: [TrackSummary]) -> [Disc] {
        let indexed = tracks.enumerated().map { (index: $0.offset, track: $0.element) }
        let grouped = Dictionary(grouping: indexed, by: \.track.discNumber)
        func rows(_ disc: [(index: Int, track: TrackSummary)]) -> [Row] {
            disc.enumerated().map { position, entry in
                Row(track: entry.track, index: entry.index, number: entry.track.trackNumber ?? position + 1)
            }
        }
        guard grouped.count > 1 else { return [Disc(number: nil, rows: rows(indexed))] }
        return grouped.keys.sorted { ($0 ?? 0) < ($1 ?? 0) }.map { Disc(number: $0, rows: rows(grouped[$0] ?? [])) }
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
