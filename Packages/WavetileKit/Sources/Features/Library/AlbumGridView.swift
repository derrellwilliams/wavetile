import DesignSystem
import GRDB
import Library
import Persistence
import SwiftUI

/// Two-column (adaptive) album grid backed by a live database query.
struct AlbumGridView: View {
    enum Source: Hashable {
        case all
        case genre(String)
    }

    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    let title: String
    let source: Source
    @State private var albums: [AlbumRecord] = []
    @State private var sort: LibraryDatabase.AlbumSort = .title

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: theme.artwork.shelfTileWidth - 8), spacing: theme.spacing.lg)],
                alignment: .leading,
                spacing: theme.spacing.xl
            ) {
                ForEach(albums) { album in
                    AlbumLink(album: album.summary)
                }
            }
            .padding(.horizontal, theme.spacing.screenInset)
            .padding(.vertical, theme.spacing.lg)
        }
        .overlay {
            if albums.isEmpty { LibraryEmptyState() }
        }
        .themedBackground()
        .navigationTitle(title)
        .toolbar {
            if source == .all {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            Text("Title").tag(LibraryDatabase.AlbumSort.title)
                            Text("Artist").tag(LibraryDatabase.AlbumSort.artist)
                            Text("Year").tag(LibraryDatabase.AlbumSort.year)
                            Text("Recently Added").tag(LibraryDatabase.AlbumSort.recentlyAdded)
                        }
                    } label: {
                        Label("Sort", glyph: .sort)
                    }
                }
            }
        }
        .task(id: sort) {
            let observation = switch source {
            case .all: store.database.albums(sort: sort)
            case let .genre(genre): store.database.albums(genre: genre)
            }
            do {
                for try await value in store.observe(observation) { albums = value }
            } catch {}
        }
        .enableInjection()
    }
}

/// Shown while the first sync hasn't produced anything yet.
struct LibraryEmptyState: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        if store.isSyncing || !store.hasSyncedOnce {
            VStack(spacing: 12) {
                LoadingMark()
                Text(store.statusText ?? "Syncing your library…")
                    .font(BrandFont.font(.subheadline))
                    .foregroundStyle(.secondary)
            }
        } else {
            EmptyState("Nothing Here", glyph: .album, message: "No matching items in your library.")
        }
    }
}
