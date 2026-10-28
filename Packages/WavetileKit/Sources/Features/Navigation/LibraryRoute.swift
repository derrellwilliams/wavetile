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
    case collection(CollectionRecord)
    case section(LibrarySection)
}

enum LibrarySection: String, CaseIterable, Hashable {
    case playlists, collections, favorites, artists, albums, songs, genres

    var title: String { rawValue.capitalized }

    var glyph: Glyph {
        switch self {
        case .playlists: .playlist
        case .collections: .collection
        case .favorites: .favorite
        case .artists: .artist
        case .albums: .album
        case .songs: .song
        case .genres: .genre
        }
    }
}

extension EnvironmentValues {
    /// The current navigation stack's namespace for zooming a page out of its artwork tile
    /// (albums, episodes, shows).
    @Entry var zoomNamespace: Namespace.ID?
    /// Pushes a route on the current tab's stack (for menus and sheets, which can't hold a NavigationLink).
    @Entry var pushLibraryRoute: (LibraryRoute) -> Void = { _ in }
}

extension View {
    /// Registers `LibraryRoute` destinations. Call once, on a tab's root screen.
    /// `zoom` is shared with pushed screens so any album tile can zoom into its page; `path` is
    /// the stack's path, so menus anywhere in the stack can push via `pushLibraryRoute`.
    func libraryDestinations(zoom: Namespace.ID, path: Binding<[LibraryRoute]>) -> some View {
        libraryDestinations(zoom: zoom) { path.wrappedValue.append($0) }
    }

    /// For stacks with a `NavigationPath` (Search and Downloaded also hold podcast routes).
    func libraryDestinations(zoom: Namespace.ID, push: @escaping (LibraryRoute) -> Void) -> some View {
        environment(\.zoomNamespace, zoom)
            .environment(\.pushLibraryRoute, push)
            .navigationDestination(for: LibraryRoute.self) { route in
                LibraryDestination(route: route, zoom: zoom)
                    .environment(\.zoomNamespace, zoom)
                    .environment(\.pushLibraryRoute, push)
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
        case let .collection(collection):
            CollectionDetailView(collection: collection)
        case .section(.collections):
            CollectionsView()
        case .section(.favorites):
            FavoritesView()
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
    @Environment(\.pushLibraryRoute) private var push
    @Environment(LibraryActions.self) private var actions
    @Environment(\.zoomNamespace) private var zoom
    let album: AlbumSummary
    /// Disambiguates the same album appearing in several places on one screen.
    var context: String = ""
    /// Adds "Remove from Recently Played" to the long-press menu (Home's Recently Played shelf).
    var onRemoveFromRecents: (() -> Void)?

    var body: some View {
        let route = AlbumRoute(album: album, sourceID: "\(context)-\(album.id)")
        NavigationLink(value: LibraryRoute.album(route)) {
            AlbumTile(
                title: album.title,
                subtitle: album.artist,
                artwork: store.artwork(itemID: album.id, tag: album.imageTag, maxPixelWidth: 480)
            )
            .zoomSource(route.sourceID, in: zoom)
        }
        .buttonStyle(.pressable)
        .contextMenu {
            Button("Add to Collection", glyph: .collection) { actions.addToCollection([album.id]) }
            Button("Favorite", glyph: .favorite) {
                actions.favorite(album.id, store: store)
            }
            // Hidden on the artist's own page.
            if context != "artist", let route = store.artistRoute(albumID: album.id) {
                Button("Go to Artist", glyph: .artist) { push(route) }
            }
            if let onRemoveFromRecents {
                Divider()
                Button("Remove from Recently Played", glyph: .close, action: onRemoveFromRecents)
            }
        }
    }
}

extension View {
    /// Marks an artwork tile as where the page it opens zooms out of.
    func zoomSource(_ id: String, in namespace: Namespace.ID?) -> some View {
        modifier(ZoomSource(id: id, namespace: namespace))
    }

    /// Zooms a pushed page out of the tile that opened it; a plain push when it wasn't a tile.
    func zoomTransition(from id: String?, in namespace: Namespace.ID?) -> some View {
        modifier(ZoomTransition(id: id, namespace: namespace))
    }
}

private struct ZoomTransition: ViewModifier {
    let id: String?
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let id, let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
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
