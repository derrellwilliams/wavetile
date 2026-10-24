import DesignSystem
import JellyfinKit
import Persistence
import SwiftUI

/// Everything on the device: downloaded albums and playlists, with progress. (Storage used is in Settings.)
struct DownloadedView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadsStore.self) private var downloads
    @Environment(Connectivity.self) private var connectivity
    @Namespace private var zoom
    @State private var collections: [DownloadedCollection] = []
    @State private var confirmRemoveAll = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.lg) {
                    if !connectivity.isOnline {
                        Label("You're offline. Downloaded music still plays.", glyph: .offline)
                            .font(theme.typography.itemSubtitle)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: theme.artwork.shelfTileWidth - 8), spacing: theme.spacing.lg)],
                        alignment: .leading,
                        spacing: theme.spacing.xl
                    ) {
                        ForEach(collections) { item in
                            tile(item)
                        }
                    }
                }
                .padding(.horizontal, theme.spacing.screenInset)
                .padding(.vertical, theme.spacing.lg)
            }
            .overlay {
                if collections.isEmpty {
                    EmptyState(
                        "No Downloads",
                        glyph: .downloads,
                        message: "Tap Download on an album or playlist to listen offline."
                    )
                }
            }
            .themedBackground()
            .navigationTitle("Downloaded")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Remove All Downloads", glyph: .trash, role: .destructive) { confirmRemoveAll = true }
                    } label: {
                        Label("More", glyph: .more)
                    }
                    .disabled(collections.isEmpty)
                }
            }
            .confirmationDialog("Remove all downloaded music?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
                Button("Remove All", role: .destructive) { downloads.removeAll() }
            } message: {
                Text("You can download it again anytime.")
            }
            .tabRootChrome()
            .libraryDestinations(zoom: zoom)
            .task {
                do {
                    for try await value in library.observe(library.database.downloadedCollections()) { collections = value }
                } catch {}
            }
        }
        .enableInjection()
    }

    @ViewBuilder private func tile(_ item: DownloadedCollection) -> some View {
        let collection = item.collection
        NavigationLink(value: route(for: collection)) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                ArtworkView(library.artwork(itemID: collection.id, tag: collection.imageTag, maxPixelWidth: 480))
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
                    .font(theme.typography.itemSubtitle)
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
