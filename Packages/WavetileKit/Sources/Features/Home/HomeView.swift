import DesignSystem
import JellyfinKit
import Persistence
import Playback
import Podcasts
import PreviewSupport
import SwiftUI

struct HomeView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(LibraryStore.self) private var store
    @Environment(Connectivity.self) private var connectivity
    @State var model: HomeModel
    @Namespace private var zoom
    @Binding var path: NavigationPath
    /// Bumped when Home's tab is tapped again; scrolls back to the top.
    let reselects: Int
    @State private var scrollPosition = ScrollPosition(edge: .top)
    /// Bumped to pull down and refresh as if the user had pulled.
    @State private var refreshRequests = 0
    @State private var didRefresh = false
    @State private var isRefreshing = false
    @State private var podcastUpNext: [EpisodeItem]
    /// Live, so a playlist or collection made elsewhere in the app shows up right away.
    @State private var playlists: [PlaylistRecord] = []
    @State private var collections: [CollectionRecord] = []
    /// Both, by name, capped: rebuilt when either list changes rather than on every render.
    @State private var libraryItems: [LibraryShelfItem] = []
    /// Downloads with something playable, for the Downloaded row that leads Home offline.
    @State private var downloads: [DownloadCollectionRecord] = []
    /// Greets a new listener by name on the welcome card.
    let userName: String

    /// `upNext` is read synchronously by the caller, so the podcast shelf is on the first frame
    /// with the music shelves instead of popping in and pushing them around.
    init(model: HomeModel, path: Binding<NavigationPath>, reselects: Int = 0, userName: String, upNext: [EpisodeItem] = []) {
        _model = State(initialValue: model)
        _path = path
        self.reselects = reselects
        self.userName = userName
        _podcastUpNext = State(initialValue: upNext)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.spacing.xxl) {
                    // Order: Recently Played, Most Played, Latest Podcast Episodes, Your Playlists &
                    // Collections, Recently Added, then up to three Artist Spotlights. The podcast
                    // shelf appears only when podcasts are on and it has something to show; the
                    // playlists and collections row only when there are some. (Continue Listening lives at the top of
                    // the Podcasts tab.) With little play history, a welcome card leads and genre
                    // shelves follow Recently Added (the card only for the first visit).
                    // Offline: say so, then lead with what still plays.
                    OfflineNotice()
                    if !connectivity.isOnline, !downloads.isEmpty {
                        ShelfSection("Downloaded", items: downloads) { DownloadLink(download: $0) }
                    }
                    if model.showsWelcome, let stats = model.stats, stats.albums > 0 {
                        WelcomeCard(userName: userName, stats: stats)
                    }
                    if podcastAnchor == nil {
                        podcastUpNextShelf
                    }
                    ForEach(model.shelves) { shelf in
                        if shelf.kind == .recentlyAdded {
                            libraryShelves
                        }
                        ShelfSection(shelf.title, items: shelf.albums) { album in
                            AlbumLink(
                                album: album,
                                context: shelf.kind.rawValue,
                                onRemoveFromRecents: shelf.kind == .recentlyPlayed
                                    ? { withAnimation(theme.motion.smooth) { model.removeFromRecentlyPlayed(album.id) } }
                                    : nil
                            )
                        }
                        if shelf.kind == podcastAnchor {
                            podcastUpNextShelf
                        }
                    }
                    if !model.shelves.contains(where: { $0.kind == .recentlyAdded }) {
                        libraryShelves
                    }
                    if model.isNewListener {
                        ForEach(model.genreShelves) { shelf in
                            ShelfSection(shelf.genre, items: shelf.albums) { album in
                                AlbumLink(album: album, context: "genre-\(shelf.genre)")
                            }
                        }
                    }
                    ForEach(model.spotlights) { spotlight in
                        ArtistSpotlightShelf(spotlight: spotlight)
                    }
                }
                .padding(.vertical, theme.spacing.lg)
            }
            .overlay { overlay }
            .themedBackground()
            // The offline notice, Downloaded row and dimming slide in and out.
            .animatesConnectivity()
            // No title on screen: the wave in the bar is Home's header. The title is for VoiceOver.
            .navigationTitle("Home")
            .toolbarTitleDisplayMode(.inline)
            .tabRootChrome(showsWave: true, onWaveTap: scrollToTop)
            .libraryDestinations(zoom: zoom) { path.append($0) }
            .podcastDestinations(zoom: zoom) { path.append($0) }
            // On the always-present scroll view: a task on a shelf that isn't shown never runs.
            // Here, not on the card: a lazy row's task is cancelled once it scrolls off. Leaving
            // Home or the app first cancels the sleep, so that minute doesn't count.
            .task(id: model.showsWelcome && scenePhase == .active) {
                guard model.showsWelcome, scenePhase == .active,
                      (try? await Task.sleep(for: .seconds(60))) != nil else { return }
                model.countWelcomeVisit()
            }
            .task { await store.observe(store.database.playableDownloads()) { downloads = $0 } }
            .task { await store.observe(store.database.playlists()) { playlists = $0; rebuildLibraryItems() } }
            .task { await store.observe(store.database.collections()) { collections = $0; rebuildLibraryItems() } }
            .task(id: podcasts.isEnabled) { await observePodcasts(podcasts.database.upNextShelf()) { podcastUpNext = $0 } }
            .markRefreshable(trigger: refreshRequests) { await refresh() }
            // Tapping Home again from a pushed screen goes back to Home; at Home, scrolled down, to the
            // top; at the top, pulled down and refreshed.
            .onTabReselect(reselects, path: $path, scrollPosition: $scrollPosition) { refreshRequests += 1 }
            .onChange(of: store.isSyncing) { _, syncing in
                guard !syncing, !isRefreshing else { return }
                Task { await model.librarySynced() }
            }
            .task {
                // Local shelves are already on screen; refresh from the server once per session.
                guard !didRefresh else { return }
                didRefresh = true
                await model.load()
                if DebugFlags.openFirstAlbum, let shelf = model.shelves.first,
                   let album = shelf.albums.dropFirst(DebugFlags.albumIndex).first {
                    path = NavigationPath([LibraryRoute.album(AlbumRoute(album: album, sourceID: "\(shelf.kind.rawValue)-\(album.id)"))])
                    if DebugFlags.openArtist, let artist = store.artistRoute(albumID: album.id) { path.append(artist) }
                }
            }
        }
        .enableInjection()
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        async let music: Void = store.syncNow()
        async let feeds: Void = refreshPodcasts()
        _ = await (music, feeds)
        model.loadDiscovery()
        await model.load()
    }

    private func refreshPodcasts() async {
        guard podcasts.isEnabled else { return }
        await podcasts.refreshAll()
    }

    /// The user's own playlists and collections in one row, by name, just above Recently Added
    /// (or where it would be).
    @ViewBuilder private var libraryShelves: some View {
        if !libraryItems.isEmpty {
            ShelfSection("Your Playlists & Collections", items: libraryItems) { item in
                switch item {
                case let .playlist(playlist): PlaylistLink(playlist: playlist)
                case let .collection(collection): CollectionLink(collection: collection)
                }
            }
        }
    }

    /// The first 16 by name; the Music tab has them all.
    private func rebuildLibraryItems() {
        libraryItems = Array(
            (playlists.map(LibraryShelfItem.playlist) + collections.map(LibraryShelfItem.collection))
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .prefix(16)
        )
    }

    private func scrollToTop() {
        withAnimation(theme.motion.smooth) { scrollPosition.scrollTo(edge: .top) }
    }

    /// The shelf Latest Podcast Episodes follows: Most Played, else Recently Played; nil puts it
    /// first among the music shelves.
    private var podcastAnchor: HomeModel.Shelf.Kind? {
        [HomeModel.Shelf.Kind.mostPlayed, .recentlyPlayed].first { kind in model.shelves.contains { $0.kind == kind } }
    }

    /// Latest Podcast Episodes: after Most Played (see `podcastAnchor`).
    @ViewBuilder private var podcastUpNextShelf: some View {
        if podcasts.isEnabled, !podcastUpNext.isEmpty, !DebugFlags.freshHome {
            EpisodeShelf(title: "Latest Podcast Episodes", items: podcastUpNext, showsStatus: false)
        }
    }

    private func observePodcasts<T: Sendable & Equatable & ExpressibleByArrayLiteral>(_ observation: GRDBObservation<T>, update: (T) -> Void) async {
        guard podcasts.isEnabled else {
            update([])
            return
        }
        await podcasts.observe(observation, animation: theme.motion.smooth, update: update)
    }

    @ViewBuilder private var overlay: some View {
        if model.isLoading {
            LoadingMark()
        } else if let error = model.errorMessage {
            EmptyState("Nothing Here Yet", message: error) {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(.tinted)
            }
        }
    }
}

#if DEBUG
#Preview {
    let app = AppModel.preview()
    if case let .signedIn(signedIn) = app.phase {
        HomeView(model: HomeModel(previewShelves: [
            .init(kind: .recentlyPlayed, albums: Array(Fixtures.albums.prefix(6))),
            .init(kind: .mostPlayed, albums: Fixtures.albums.reversed()),
            .init(kind: .recentlyAdded, albums: Array(Fixtures.albums.suffix(5))),
        ]), path: .constant(NavigationPath()), userName: Fixtures.session.userName)
        .environment(signedIn.library)
        .environment(signedIn.podcasts)
    }
}
#endif

/// A tile in Home's playlists and collections row.
private enum LibraryShelfItem: Identifiable {
    case playlist(PlaylistRecord)
    case collection(CollectionRecord)

    var id: String {
        switch self {
        case let .playlist(playlist): "playlist-\(playlist.id)"
        case let .collection(collection): "collection-\(collection.id)"
        }
    }

    var name: String {
        switch self {
        case let .playlist(playlist): playlist.name
        case let .collection(collection): collection.name
        }
    }
}
