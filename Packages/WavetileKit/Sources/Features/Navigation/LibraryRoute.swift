import DesignSystem
import JellyfinKit
import Persistence
import SwiftUI

/// Every library destination, shared by the Home, Library and Search stacks.
enum LibraryRoute: Hashable {
    case album(AlbumRoute)
    case artist(id: String, name: String)
    case genre(String)
    case playlist(PlaylistRecord)
    case section(LibrarySection)
}

enum LibrarySection: String, CaseIterable, Hashable {
    case playlists, artists, albums, songs, genres

    var title: String { rawValue.capitalized }

    var glyph: Glyph {
        switch self {
        case .playlists: .playlist
        case .artists: .artist
        case .albums: .album
        case .songs: .song
        case .genres: .genre
        }
    }
}

extension EnvironmentValues {
    /// The current navigation stack's namespace for album zoom transitions.
    @Entry var libraryZoom: Namespace.ID?
}

extension View {
    /// Registers `LibraryRoute` destinations. Call once, on a tab's root screen.
    /// `zoom` is shared with pushed screens so any album tile can zoom into its page.
    func libraryDestinations(zoom: Namespace.ID) -> some View {
        environment(\.libraryZoom, zoom)
            .navigationDestination(for: LibraryRoute.self) { route in
                LibraryDestination(route: route, zoom: zoom)
                    .environment(\.libraryZoom, zoom)
            }
    }
}

private struct LibraryDestination: View {
    @Environment(LibraryStore.self) private var store
    let route: LibraryRoute
    let zoom: Namespace.ID

    var body: some View {
        switch route {
        case let .album(album):
            AlbumDetailView(model: AlbumDetailModel(album: album.album, store: store))
                .navigationTransition(.zoom(sourceID: album.sourceID, in: zoom))
        case let .artist(id, name):
            ArtistDetailView(artistID: id, name: name)
        case let .genre(genre):
            AlbumGridView(title: genre, source: .genre(genre))
        case let .playlist(playlist):
            PlaylistDetailView(playlist: playlist)
        case .section(.albums):
            AlbumGridView(title: "Albums", source: .all)
        case .section(.artists):
            ArtistsView()
        case .section(.songs):
            SongsView()
        case .section(.genres):
            GenresView()
        case .section(.playlists):
            PlaylistsView()
        }
    }
}

/// Album tile that pushes the album with a zoom transition from the tapped artwork.
struct AlbumLink: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.libraryZoom) private var zoom
    let album: AlbumSummary
    /// Disambiguates the same album appearing in several places on one screen.
    var context: String = ""

    var body: some View {
        let route = AlbumRoute(album: album, sourceID: "\(context)-\(album.id)")
        NavigationLink(value: LibraryRoute.album(route)) {
            AlbumTile(
                title: album.title,
                subtitle: album.artist,
                artwork: store.artwork(itemID: album.id, tag: album.imageTag, maxPixelWidth: 480)
            )
            .modifier(ZoomSource(id: route.sourceID, namespace: zoom))
        }
        .buttonStyle(.pressable)
    }
}

private struct ZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}
