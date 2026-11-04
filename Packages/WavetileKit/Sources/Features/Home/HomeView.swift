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
    @State var model: HomeModel
    @Namespace private var zoom
    @Binding var path: NavigationPath
    /// Bumped when Home's tab is tapped again; scrolls back to the top.
    let reselects: Int
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var didRefresh = false
    @State private var podcastUpNext: [EpisodeItem]
    /// Live, so a playlist or collection made elsewhere in the app shows up right away.
    @State private var playlists: [PlaylistRecord] = []
    @State private var collections: [CollectionRecord] = []
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
                    // Order: Recently Played, Latest Podcast Episodes, Most Played, Playlists,
                    // Collections, Recently Added, then up to three Artist Spotlights. Latest Podcast
                    // Episodes appears only when podcasts are on and it has episodes; Playlists and
                    // Collections only when there are some. (Continue Listening lives at the top of
                    // the Podcasts tab.) With little play history, a welcome card leads and genre
                    // shelves follow Recently Added (the card only for the first visit).
                    if model.showsWelcome, let stats = model.stats, stats.albums > 0 {
                        WelcomeCard(userName: userName, stats: stats)
                    }
                    if !hasRecentlyPlayed {
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
                        if shelf.kind == .recentlyPlayed {
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
            .scrollPosition($scrollPosition)
            .overlay { overlay }
            .themedBackground()
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
            .task { await observe(store.database.playlists()) { playlists = $0 } }
            .task { await observe(store.database.collections()) { collections = $0 } }
            .task(id: podcasts.isEnabled) { await observePodcasts(podcasts.database.upNextShelf()) { podcastUpNext = $0 } }
            .markRefreshable {
                await model.loadDiscovery()
                await model.load()
            }
            // First launch: the library is still syncing when Home appears.
            .onChange(of: reselects) {
                // Tapping Home again from a pushed screen goes back to Home; at Home, to the top.
                if path.isEmpty { scrollToTop() } else { path = NavigationPath() }
            }
            .onChange(of: store.isSyncing) { _, syncing in
                guard !syncing else { return }
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

    /// The user's own playlists and collections, just above Recently Added (or where it would be).
    @ViewBuilder private var libraryShelves: some View {
        if !playlists.isEmpty {
            ShelfSection("Playlists", items: playlists) { PlaylistLink(playlist: $0) }
        }
        if !collections.isEmpty {
            ShelfSection("Collections", items: collections) { CollectionLink(collection: $0) }
        }
    }

    private func observe<T: Sendable & Equatable>(_ observation: GRDBObservation<T>, update: (T) -> Void) async {
        do {
            for try await value in store.observe(observation) { update(value) }
        } catch { Log.observationFailed(error) }
    }

    private func scrollToTop() {
        withAnimation(theme.motion.smooth) { scrollPosition.scrollTo(edge: .top) }
    }

    private var hasRecentlyPlayed: Bool {
        model.shelves.contains { $0.kind == .recentlyPlayed }
    }

    /// Latest Podcast Episodes: after Recently Played, or first among the music shelves without it.
    @ViewBuilder private var podcastUpNextShelf: some View {
        if podcasts.isEnabled, !podcastUpNext.isEmpty, !DebugFlags.freshHome {
            EpisodeShelf(title: "Latest Podcast Episodes", items: podcastUpNext, showsStatus: false)
        }
    }

    private func observePodcasts(_ observation: GRDBObservation<[EpisodeItem]>, update: ([EpisodeItem]) -> Void) async {
        guard podcasts.isEnabled else {
            update([])
            return
        }
        do {
            // The first load appears as-is; later changes animate.
            var loaded = false
            for try await items in podcasts.observe(observation) {
                withAnimation(loaded ? theme.motion.smooth : nil) { update(items) }
                loaded = true
            }
        } catch { Log.observationFailed(error) }
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
