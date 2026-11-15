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
            songRoutes(
                albumID: track.albumID, albumTitle: track.albumTitle, albumArtist: track.albumArtistName,
                sourceID: "\(source)-track-\(track.id)"
            )
        }
    }

    /// A song's album and artist pages, from one album read. The album falls back to the song's
    /// own album fields when the mirror has no row for it; the artist is the album artist
    /// (tracks don't store their own artist ID), so it needs the row.
    func songRoutes(
        albumID: String?, albumTitle: String, albumArtist: String, sourceID: String
    ) -> (album: LibraryRoute?, artist: LibraryRoute?) {
        guard let albumID else { return (nil, nil) }
        let record = try? database.album(id: albumID)
        let album = LibraryRoute.album(AlbumRoute(
            album: record?.summary ?? AlbumSummary(id: albumID, title: albumTitle, artist: albumArtist),
            sourceID: sourceID
        ))
        let artist = record.flatMap { record in record.artistID.map { LibraryRoute.artist(id: $0, name: record.artistName) } }
        return (album, artist)
    }
}
