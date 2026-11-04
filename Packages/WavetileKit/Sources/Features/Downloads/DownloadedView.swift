import DesignSystem
import JellyfinKit
import Persistence
import Podcasts
import SwiftUI

/// Everything on the device: downloaded albums and playlists, with progress, and (with podcasts
/// on) downloaded episodes behind a Music | Podcasts filter. (Storage used is in Settings.)
struct DownloadedView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadsStore.self) private var downloads
    @Environment(Connectivity.self) private var connectivity
    @Environment(PodcastsStore.self) private var podcasts
    @Namespace private var zoom
    @State private var path = NavigationPath()
    @State private var collections: [DownloadedCollection] = []
    @State private var confirmRemoveAll = false
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
                    filterHeader
                    if showsPodcasts { podcastContent } else { musicContent }
                }
            }
            .themedBackground()
            .navigationTitle("Downloads")
            .confirmationDialog(showsPodcasts ? "Remove all downloaded episodes?" : "Remove all downloaded music?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
                Button("Remove All", role: .destructive) {
                    if showsPodcasts { podcasts.removeAllDownloads() } else { downloads.removeAll() }
                }
            } message: {
                Text("You can download it again anytime.")
            }
            .tabRootChrome {
                Menu {
                    Button("Remove All Downloads", glyph: .trash, role: .destructive) { confirmRemoveAll = true }
                } label: {
                    TintedBarIcon(glyph: .more)
                }
                .accessibilityLabel("More")
                .disabled(showsPodcasts ? episodes.isEmpty : collections.isEmpty)
            }
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
            if !connectivity.isOnline {
                Label(connectivity.hasNetwork ? "Can't reach your server. Downloaded music still plays." : "You're offline. Downloaded music still plays.", glyph: .offline)
                    .font(theme.typography.itemSubtitle)
                    .foregroundStyle(theme.palette.textSecondary)
                    // Drops in from the top and leaves the same way.
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, theme.spacing.screenInset)
            }
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
        .animation(theme.motion.smooth, value: connectivity.isOnline)
    }

    @ViewBuilder private func tile(_ item: DownloadedCollection) -> some View {
        let collection = item.collection
        NavigationLink(value: route(for: collection)) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                ArtworkView(collection.kind == .playlist
                            ? library.cover(for: collection.id, tag: collection.imageTag, maxPixelWidth: 480)
                            : library.artwork(itemID: collection.id, tag: collection.imageTag, maxPixelWidth: 480))
                    .overlay(alignment: .bottomTrailing) {
                        if item.status.isInProgress {
                            ProgressRing(progress: item.status.progress)
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
            Button("Remove Download", glyph: .trash, role: .destructive) {
                downloads.remove(collectionID: collection.id)
            }
        }
    }

    private func subtitle(_ item: DownloadedCollection) -> String {
        if item.status.isInProgress { return "\(item.status.done) of \(item.status.total) songs" }
        if item.status.failed > 0 { return "\(item.status.failed) failed" }
        return "\(item.collection.subtitle) · \(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))"
    }

    private func route(for collection: DownloadCollectionRecord) -> LibraryRoute {
        switch collection.kind {
        case .album:
            let year = (try? library.database.album(id: collection.id))?.year
            let album = AlbumSummary(id: collection.id, title: collection.name, artist: collection.subtitle, year: year, imageTag: collection.imageTag)
            return .album(AlbumRoute(album: album, sourceID: "downloaded-\(collection.id)"))
        case .playlist:
            let playlist = (try? library.database.pool.read { try PlaylistRecord.fetchOne($0, key: collection.id) })
                ?? PlaylistRecord(id: collection.id, name: collection.name, imageTag: collection.imageTag, trackCount: 0, durationMs: 0, generation: 0)
            return .playlist(playlist)
        }
    }
}
