import DesignSystem
import JellyfinKit
import Playback
import Podcasts
import PreviewSupport
import SwiftUI

struct HomeView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(LibraryStore.self) private var store
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    @Environment(Connectivity.self) private var connectivity
    @State var model: HomeModel
    @Namespace private var zoom
    @Binding var path: NavigationPath
    @State private var didRefresh = false
    @State private var podcastUpNext: [EpisodeItem]

    /// `upNext` is read synchronously by the caller, so the podcast shelf is on the first frame
    /// with the music shelves instead of popping in and pushing them around.
    init(model: HomeModel, path: Binding<NavigationPath>, upNext: [EpisodeItem] = []) {
        _model = State(initialValue: model)
        _path = path
        _podcastUpNext = State(initialValue: upNext)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.spacing.xxl) {
                    // Order: Recently Played, Up Next in Podcasts, Most Played, Recently Added,
                    // From Your Library, Artist Spotlight. Up Next appears only when podcasts are
                    // on and it has episodes. (Continue Listening lives at the top of the Podcasts
                    // tab.) With little play history, a welcome card leads and genre and playlist
                    // shelves follow Recently Added.
                    if model.isNewListener, let stats = model.stats, stats.albums > 0 {
                        WelcomeCard(stats: stats, onShuffle: shuffleAll) {
                            path.append(LibraryRoute.section(.genres))
                        }
                    }
                    if !hasRecentlyPlayed {
                        podcastUpNextShelf
                    }
                    ForEach(model.shelves) { shelf in
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
                    if model.isNewListener {
                        ForEach(model.genreShelves) { shelf in
                            ShelfSection(shelf.genre, items: shelf.albums, onTitleTap: {
                                path.append(LibraryRoute.genre(shelf.genre))
                            }) { album in
                                AlbumLink(album: album, context: "genre-\(shelf.genre)")
                            }
                        }
                        if !model.playlists.isEmpty {
                            ShelfSection("Playlists", items: model.playlists, onTitleTap: {
                                path.append(LibraryRoute.section(.playlists))
                            }) { playlist in
                                PlaylistLink(playlist: playlist)
                            }
                        }
                    }
                    if !model.rediscover.isEmpty {
                        ShelfSection("From Your Library", items: model.rediscover) { album in
                            AlbumLink(album: album, context: "rediscover")
                        }
                    }
                    if let spotlight = model.spotlight, !spotlight.albums.isEmpty {
                        ArtistSpotlightShelf(spotlight: spotlight) {
                            path.append(LibraryRoute.artist(id: spotlight.artistID, name: spotlight.name))
                        }
                    }
                }
                .padding(.vertical, theme.spacing.lg)
            }
            .overlay { overlay }
            .themedBackground()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Wavetile")
                        .font(theme.typography.wordmark)
                        .foregroundStyle(theme.palette.accent)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .tabRootChrome()
            .libraryDestinations(zoom: zoom) { path.append($0) }
            .podcastDestinations { path.append($0) }
            // On the always-present scroll view: a task on a shelf that isn't shown never runs.
            .task(id: podcasts.isEnabled) { await observePodcasts(podcasts.database.upNextShelf()) { podcastUpNext = $0 } }
            .markRefreshable {
                await model.loadDiscovery()
                await model.load()
            }
            // First launch: the library is still syncing when Home appears.
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
                }
            }
        }
        .enableInjection()
    }

    /// Plays a random sample of the library (offline, only what's downloaded).
    private func shuffleAll() {
        let tracks = model.shuffleAllTracks()
        guard connectivity.isOnline || tracks.contains(where: { downloads.isDownloaded($0.id) }) else { return }
        player.play(tracks.map(QueuedTrack.init), startAt: 0, online: connectivity.isOnline, downloads: downloads)
    }

    private var hasRecentlyPlayed: Bool {
        model.shelves.contains { $0.kind == .recentlyPlayed }
    }

    /// Up Next in Podcasts: after Recently Played, or first among the music shelves without it.
    @ViewBuilder private var podcastUpNextShelf: some View {
        if podcasts.isEnabled, !podcastUpNext.isEmpty, !DebugFlags.freshHome {
            EpisodeShelf(title: "Up Next in Podcasts", items: podcastUpNext)
        }
    }

    private func observePodcasts(_ observation: GRDBObservation<[EpisodeItem]>, update: ([EpisodeItem]) -> Void) async {
        guard podcasts.isEnabled else {
            update([])
            return
        }
        do {
            for try await items in podcasts.observe(observation) {
                withAnimation(theme.motion.smooth) { update(items) }
            }
        } catch { Log.observationFailed(error) }
    }

    @ViewBuilder private var overlay: some View {
        if model.isLoading {
            LoadingMark()
        } else if let error = model.errorMessage {
            EmptyState("Nothing Here Yet", glyph: .album, message: error) {
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(.glass)
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
        ]), path: .constant(NavigationPath()))
        .environment(signedIn.library)
        .environment(signedIn.podcasts)
    }
}
