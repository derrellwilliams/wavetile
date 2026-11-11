import DesignSystem
import JellyfinKit
import Persistence
import Podcasts
import SwiftUI

/// Everything on the device: downloaded albums and playlists, with progress, and (with podcasts
/// on) downloaded episodes behind a Music | Podcasts filter. (Sizes live in `StorageView`.)
struct DownloadedView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadsStore.self) private var downloads
    @Environment(PodcastsStore.self) private var podcasts
    @Namespace private var zoom
    let reselects: Int
    @State private var path = NavigationPath()
    /// Driven by `onTabReselect`: a tab tap scrolls to the top.
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var statusCollection: DownloadCollectionRecord?
    @State private var collections: [DownloadedCollection] = []
    @State private var confirmRemoveAll = false
    @State private var showStorage = false
    @State private var filter: MediaKind = .music
    @State private var episodes: [EpisodeItem] = []
    /// Set after each list's first read, so its empty state doesn't flash in before it loads.
    @State private var collectionsLoaded = false
    @State private var episodesLoaded = false

    private var showsPodcasts: Bool { podcasts.isEnabled && filter == .podcasts }

    var body: some View {
        NavigationStack(path: $path) {
            // One scroll view for both filters: swapping whole scroll views made the large title
            // flash on every switch, since it follows whichever one is on screen.
            ScrollView {
                VStack(spacing: 0) {
                    OfflineNotice(gap: theme.spacing.md)
                    filterHeader
                    if showsPodcasts { podcastContent } else { musicContent }
                }
                .animatesConnectivity()
            }
            .themedBackground()
            .navigationTitle("Downloads")
            .onTabReselect(reselects, path: $path, scrollPosition: $scrollPosition)
            .sheet(item: $statusCollection) { DownloadStatusSheet(collectionID: $0.id) }
            .confirmationDialog(showsPodcasts ? "Remove all downloaded episodes?" : "Remove all downloaded music?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
                Button("Remove All", role: .destructive) {
                    if showsPodcasts { podcasts.removeAllDownloads() } else { downloads.removeAll() }
                }
            } message: {
                Text("You can download it again anytime.")
            }
            .tabRootChrome {
                Menu {
                    Button("Manage Storage", glyph: .downloads) { showStorage = true }
                    Button("Remove All Downloads", glyph: .trash, role: .destructive) { confirmRemoveAll = true }
                        .disabled(showsPodcasts ? episodes.isEmpty : collections.isEmpty)
                } label: {
                    TintedBarIcon(glyph: .more)
                }
                .accessibilityLabel("More")
            }
            .sheet(isPresented: $showStorage) { StorageView() }
            .libraryDestinations(zoom: zoom) { path.append($0) }
            .podcastDestinations(zoom: zoom) { path.append($0) }
            .task {
                do {
                    for try await value in library.observe(library.database.downloadedCollections()) {
                        // The first load appears as-is; later changes (removals, new downloads) animate.
                        if collections.isEmpty { collections = value } else {
                            withAnimation(theme.motion.smooth) { collections = value }
                        }
                        collectionsLoaded = true
                    }
                } catch { Log.observationFailed(error) }
            }
            .task {
                do {
                    for try await value in podcasts.observe(podcasts.database.downloads()) {
                        if episodes.isEmpty { episodes = value } else {
                            withAnimation(theme.motion.smooth) { episodes = value }
                        }
                        episodesLoaded = true
                    }
                } catch { Log.observationFailed(error) }
            }
        }
        .enableInjection()
    }

    @ViewBuilder private var podcastContent: some View {
        if episodesLoaded, episodes.isEmpty {
            EmptyPrompt("No Downloaded Episodes Yet", message: "Download any episode to listen without a connection.")
                .padding(.top, theme.spacing.lg)
        } else {
            PodcastDownloadsList(items: episodes)
        }
    }

    /// Scrolls with the content (not pinned) so the large title and filter move together;
    /// a pinned filter let the title slide under it on overscroll.
    @ViewBuilder private var filterHeader: some View {
        if podcasts.isEnabled { MediaFilter(selection: $filter) }
    }

    private var musicContent: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            if collectionsLoaded, collections.isEmpty {
                EmptyPrompt("No Downloaded Music Yet", message: "Download any album or playlist to play it without a connection.")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: theme.artwork.shelfTileWidth - 8), spacing: theme.spacing.lg)],
                    alignment: .leading,
                    spacing: theme.spacing.xl
                ) {
                    ForEach(collections) { item in
                        tile(item)
                            // Removing a download fades the tile out; the rest slide into place.
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, theme.spacing.screenInset)
            }
        }
        .padding(.vertical, theme.spacing.lg)
    }

    @ViewBuilder private func tile(_ item: DownloadedCollection) -> some View {
        let collection = item.collection
        NavigationLink(value: library.route(for: collection)) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                ArtworkView(library.artwork(for: collection, maxPixelWidth: 480))
                    .overlay(alignment: .bottomTrailing) {
                        if item.status.isInProgress || item.status.paused > 0 {
                            Button { statusCollection = collection } label: {
                                ProgressRing(progress: item.status.progress)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Download status")
                                .frame(width: 22, height: 22)
                                .padding(6)
                                .background(.black.opacity(0.55), in: .circle)
                                .padding(theme.spacing.sm)
                        }
                    }
                Text(collection.name)
                    .font(theme.typography.itemTitle)
                    .foregroundStyle(theme.palette.textPrimary)
                Text(subtitle(item))
                    .font(theme.typography.itemMetadata)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .lineLimit(1)
        }
        .buttonStyle(.pressable)
        .contextMenu {
            Button("Download Status") { statusCollection = collection }
            Button("Remove Download", glyph: .trash, role: .destructive) {
                downloads.remove(collectionID: collection.id)
            }
        }
    }

    private func subtitle(_ item: DownloadedCollection) -> String {
        if item.status.paused > 0 { return "Paused · \(item.status.done) of \(item.status.total) songs" }
        if item.status.isInProgress { return "\(item.status.done) of \(item.status.total) songs" }
        if item.status.failed > 0 { return "\(item.status.failed) failed" }
        return item.collection.subtitle
    }
}

extension LibraryStore {
    /// Where a download opens: its album, playlist or collection page, or Favorites.
    func route(for download: DownloadCollectionRecord) -> LibraryRoute {
        switch download.kind {
        case .album:
            let year = (try? database.album(id: download.id))?.year
            let album = AlbumSummary(id: download.id, title: download.name, artist: download.subtitle, year: year, imageTag: download.imageTag)
            return .album(AlbumRoute(album: album, sourceID: "downloaded-\(download.id)"))
        case .playlist:
            let playlist = (try? database.playlist(id: download.id))
                ?? PlaylistRecord(id: download.id, name: download.name, imageTag: download.imageTag, trackCount: 0, durationMs: 0, generation: 0)
            return .playlist(playlist)
        case .collection:
            let record = (try? database.collection(id: download.id))
                ?? CollectionRecord(id: download.id, name: download.name, sortName: download.name, imageTag: download.imageTag, albumCount: 0, generation: 0)
            return .collection(record)
        case .favorites:
            return .section(.favorites)
        }
    }

    /// A download's art: an album's own, or the cover of a playlist, collection or Favorites
    /// (server art, or the generated one).
    func artwork(for download: DownloadCollectionRecord, maxPixelWidth: Int) -> ArtworkSource {
        download.kind == .album
            ? artwork(itemID: download.id, tag: download.imageTag, maxPixelWidth: maxPixelWidth)
            : cover(for: download.id, tag: download.imageTag, maxPixelWidth: maxPixelWidth)
    }
}
