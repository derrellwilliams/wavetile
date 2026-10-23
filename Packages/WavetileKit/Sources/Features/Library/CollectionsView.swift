import DesignSystem
import Library
import Persistence
import SwiftUI

/// Album-based collections (Jellyfin Collections). The counterpart to song-based playlists.
struct CollectionsView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    @State private var collections: [CollectionRecord] = []
    @State private var showNew = false
    @State private var newName = ""
    @State private var pendingDelete: CollectionRecord?

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: theme.artwork.shelfTileWidth - 8), spacing: theme.spacing.lg)],
                alignment: .leading,
                spacing: theme.spacing.xl
            ) {
                ForEach(collections) { collection in
                    NavigationLink(value: LibraryRoute.collection(collection)) {
                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            CollectionMosaic(collectionID: collection.id)
                            Text(collection.name)
                                .font(theme.typography.itemTitle)
                                .foregroundStyle(theme.palette.textPrimary)
                            Text("\(collection.albumCount) album\(collection.albumCount == 1 ? "" : "s")")
                                .font(theme.typography.itemSubtitle)
                                .foregroundStyle(theme.palette.textSecondary)
                        }
                        .lineLimit(1)
                    }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        Button("Delete Collection", glyph: .trash, role: .destructive) { pendingDelete = collection }
                    }
                }
            }
            .padding(.horizontal, theme.spacing.screenInset)
            .padding(.vertical, theme.spacing.lg)
        }
        .overlay {
            if collections.isEmpty {
                EmptyState("No Collections", glyph: .collection, message: "Group albums into collections. Tap + or use “Add to Collection” on any album.")
            }
        }
        .themedBackground()
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Collection", glyph: .add) { showNew = true }
            }
        }
        .alert("New Collection", isPresented: $showNew) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                newName = ""
                guard !name.isEmpty else { return }
                Task {
                    do { try await store.editor.createCollection(name: name) } catch {
                        actions.errorMessage = "Couldn't create the collection. Check your connection."
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                guard let collection = pendingDelete else { return }
                Task {
                    do { try await store.editor.deleteCollection(id: collection.id) } catch {
                        actions.errorMessage = "Couldn't delete the collection."
                    }
                }
            }
        } message: {
            Text("The albums stay in your library.")
        }
        .task {
            do {
                for try await value in store.observe(store.database.collections()) { collections = value }
            } catch {}
        }
        .enableInjection()
    }
}

struct CollectionDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    let collection: CollectionRecord
    @State private var albums: [AlbumRecord] = []
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: theme.artwork.shelfTileWidth - 8), spacing: theme.spacing.lg)],
                alignment: .leading,
                spacing: theme.spacing.xl
            ) {
                ForEach(albums) { album in
                    AlbumLink(album: album.summary, context: "collection")
                        .contextMenu {
                            Button("Remove from Collection", glyph: .trash, role: .destructive) {
                                Task {
                                    do { try await store.editor.removeFromCollection(id: collection.id, albumIDs: [album.id]) } catch {
                                        actions.errorMessage = "Couldn't update the collection."
                                    }
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, theme.spacing.screenInset)
            .padding(.vertical, theme.spacing.lg)
        }
        .overlay {
            if albums.isEmpty {
                EmptyState("Empty Collection", glyph: .collection, message: "Use “Add to Collection” on an album to add it here.")
            }
        }
        .themedBackground()
        .navigationTitle(collection.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete Collection", glyph: .trash, role: .destructive) { confirmDelete = true }
                } label: {
                    Label("More", glyph: .more)
                }
            }
        }
        .confirmationDialog("Delete “\(collection.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Collection", role: .destructive) {
                Task {
                    do {
                        try await store.editor.deleteCollection(id: collection.id)
                        dismiss()
                    } catch {
                        actions.errorMessage = "Couldn't delete the collection."
                    }
                }
            }
        } message: {
            Text("The albums stay in your library.")
        }
        .task {
            do {
                for try await value in store.observe(store.database.albums(collectionID: collection.id)) { albums = value }
            } catch {}
        }
        .enableInjection()
    }
}

/// 2×2 grid of the collection's first album covers (Jellyfin rarely has collection art).
struct CollectionMosaic: View {
    @Environment(LibraryStore.self) private var store
    let collectionID: String
    @State private var covers: [AlbumRecord] = []

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if covers.count >= 4 {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow { cover(0); cover(1) }
                        GridRow { cover(2); cover(3) }
                    }
                } else if let first = covers.first {
                    ArtworkView(store.artwork(itemID: first.id, tag: first.imageTag, maxPixelWidth: 480), cornerRadius: 0)
                } else {
                    ArtworkView(.placeholder(seed: collectionID.count), cornerRadius: 0)
                }
            }
            .clipped()
            .task(id: collectionID) {
                covers = (try? store.database.collectionCovers(collectionID: collectionID)) ?? []
            }
    }

    private func cover(_ index: Int) -> some View {
        ArtworkView(store.artwork(itemID: covers[index].id, tag: covers[index].imageTag, maxPixelWidth: 240), cornerRadius: 0)
    }
}
