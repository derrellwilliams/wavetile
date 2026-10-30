import DesignSystem
import JellyfinKit
import Persistence
import Playback
import SwiftUI

/// What a song's ⋯ menu and long press both offer beyond the standard queue actions:
/// play it, or jump to its album or artist (nil when the song isn't linked to a synced album).
struct SongMenu {
    let play: () -> Void
    private let routes: Routes

    /// Rows build a menu on every render; the routes need a database read, so they're resolved
    /// once, when the menu first asks for them.
    private final class Routes {
        let resolve: () -> (album: LibraryRoute?, artist: LibraryRoute?)
        lazy var value = resolve()
        init(_ resolve: @escaping () -> (album: LibraryRoute?, artist: LibraryRoute?)) { self.resolve = resolve }
    }

    init(play: @escaping () -> Void, routes: @escaping () -> (album: LibraryRoute?, artist: LibraryRoute?)) {
        self.play = play
        self.routes = Routes(routes)
    }

    var album: LibraryRoute? { routes.value.album }
    var artist: LibraryRoute? { routes.value.artist }
}

extension LibraryStore {
    /// The song's album page, or nil when the song isn't linked to an album.
    func artistRoute(albumID: String) -> LibraryRoute? {
        guard let album = try? database.album(id: albumID), let artistID = album.artistID else { return nil }
        return .artist(id: artistID, name: album.artistName)
    }

    func songMenu(for track: TrackRecord, source: String, play: @escaping () -> Void) -> SongMenu {
        SongMenu(play: play) { [self] in
            // One album read serves both routes. The artist is the album artist: tracks don't
            // store their own artist ID.
            let record = albumRecord(for: track)
            let album = track.albumID.map { albumID in
                LibraryRoute.album(AlbumRoute(
                    album: record?.summary ?? AlbumSummary(id: albumID, title: track.albumTitle, artist: track.albumArtistName),
                    sourceID: "\(source)-track-\(track.id)"
                ))
            }
            let artist = record.flatMap { record in record.artistID.map { LibraryRoute.artist(id: $0, name: record.artistName) } }
            return (album, artist)
        }
    }

    private func albumRecord(for track: TrackRecord) -> AlbumRecord? {
        track.albumID.flatMap { try? database.album(id: $0) }
    }
}
