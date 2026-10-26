import DesignSystem
import JellyfinKit
import Podcasts
import PreviewSupport
import SwiftUI

struct HomeView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    @State var model: HomeModel
    @Namespace private var zoom
    @Binding var path: NavigationPath
    @State private var didRefresh = false
    @State private var podcastUpNext: [EpisodeItem] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.spacing.xxl) {
                    // Order: Recently Played, Up Next in Podcasts, Most Played, Recently Added.
                    // Up Next appears only when podcasts are on and it has episodes. (Continue
                    // Listening lives at the top of the Podcasts tab.)
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
            .markRefreshable { await model.load() }
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

    private var hasRecentlyPlayed: Bool {
        model.shelves.contains { $0.kind == .recentlyPlayed }
    }

    /// Up Next in Podcasts: after Recently Played, or first among the music shelves without it.
    @ViewBuilder private var podcastUpNextShelf: some View {
        if podcasts.isEnabled, !podcastUpNext.isEmpty {
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
