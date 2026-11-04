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
    @State private var pickingCover: String?

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
                            ArtworkView(store.cover(for: collection.id, tag: collection.imageTag, maxPixelWidth: 480))
                            Text(collection.name)
                                .font(theme.typography.itemTitle)
                                .foregroundStyle(theme.palette.textPrimary)
                            Text("\(collection.albumCount) album\(collection.albumCount == 1 ? "" : "s")")
                                .font(theme.typography.itemMetadata)
                                .foregroundStyle(theme.palette.textSecondary)
                        }
                        .lineLimit(1)
                    }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        CoverMenuItems(itemID: collection.id, imageTag: collection.imageTag, owner: .collection, pickingCover: $pickingCover)
                        Button("Delete Collection", glyph: .trash, role: .destructive) { pendingDelete = collection }
                    }
                }
            }
            .padding(.horizontal, theme.spacing.screenInset)
            .padding(.vertical, theme.spacing.lg)
        }
        .overlay {
            if collections.isEmpty {
                EmptyState("No Collections", message: "Group albums into collections. Tap + or use “Add to Collection” on any album.")
            }
        }
        .themedBackground()
        .navigationTitle("Collections")
        .coverImagePicker(itemID: $pickingCover, owner: .collection)
        .listBar {
            Button { showNew = true } label: { TintedBarIcon(glyph: .add) }
                .accessibilityLabel("New Collection")
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
                        actions.editFailed("create collections", error)
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
                        actions.editFailed("delete this collection", error)
                    }
                }
            }
        } message: {
            Text("The albums stay in your library.")
        }
        .task {
            do {
                for try await value in store.observe(store.database.collections()) { collections = value }
            } catch { Log.observationFailed(error) }
        }
        .enableInjection()
    }
}

/// Collection page: full-bleed cover, name and album count, then the albums. Like a playlist page.
struct CollectionDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    @State private var collection: CollectionRecord
    @State private var albums: [AlbumRecord] = []
    /// Set after the first read, so the empty state doesn't flash before the albums arrive.
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var pickingCover: String?
    @State private var showRename = false
    @State private var newName = ""
    @State private var showPicker = false

    init(collection: CollectionRecord) {
        _collection = State(initialValue: collection)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: theme.spacing.md) {
                    ArtworkHero(artwork: store.cover(for: collection.id, tag: collection.imageTag, maxPixelWidth: 1320))
                    DetailHeader(collection.name, metadata: "\(collection.albumCount) album\(collection.albumCount == 1 ? "" : "s")")
                }
                if loaded, albums.isEmpty {
                    emptyState
                }
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
                                            actions.editFailed("remove albums from this collection", error)
                                        }
                                    }
                                }
                            }
                    }
                }
                .padding(.horizontal, theme.spacing.screenInset)
                .padding(.vertical, theme.spacing.lg)
            }
            .padding(.bottom, theme.spacing.xxl)
        }
        // Full-bleed art: no bar background or blur band under the navigation bar.
        .detailPageChrome()
        .detailBarButtons {
            Menu {
                if store.canRenameCollections {
                    Button("Rename", glyph: .edit) {
                        newName = collection.name
                        showRename = true
                    }
                }
                CoverMenuItems(itemID: collection.id, imageTag: collection.imageTag, owner: .collection, pickingCover: $pickingCover)
                Divider()
                Button("Delete Collection", glyph: .trash, role: .destructive) { confirmDelete = true }
            } label: {
                TintedBarIcon(glyph: .more)
            }
            .accessibilityLabel("More")
        }
        .alert("Rename Collection", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name != collection.name else { return }
                Task {
                    do {
                        let newID = try await store.editor.renameCollection(id: collection.id, to: name)
                        // Renamed by recreating: follow the new collection.
                        if newID != collection.id {
                            store.moveCoverShuffle(from: collection.id, to: newID)
                            if let record = try? store.database.collection(id: newID) { collection = record }
                        }
                    } catch is LibraryEditor.DuplicateCollectionError {
                        actions.errorMessage = "Renamed, but the old copy couldn't be removed, so both are on your server. Delete the old one from Jellyfin."
                    } catch {
                        actions.editFailed("rename this collection", error)
                    }
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
                        actions.editFailed("delete this collection", error)
                    }
                }
            }
        } message: {
            Text("The albums stay in your library.")
        }
        .coverImagePicker(itemID: $pickingCover, owner: .collection)
        .sheet(isPresented: $showPicker) {
            LibraryPicker(target: .collection(id: collection.id))
                .presentationBackground(theme.palette.background)
        }
        .task(id: collection.id) { await observe() }
        .enableInjection()
    }

    private func observe() async {
        async let albums: Void = observeAlbums()
        async let record: Void = observeRecord()
        _ = await (albums, record)
    }

    private func observeAlbums() async {
        do {
            for try await value in store.observe(store.database.albums(collectionID: collection.id)) {
                albums = value
                loaded = true
            }
        } catch { Log.observationFailed(error) }
    }

    /// Keeps the cover, name and count current after uploads, shuffles and edits.
    private func observeRecord() async {
        do {
            for try await value in store.observe(store.database.collectionObservation(id: collection.id)) {
                if let value { collection = value }
            }
        } catch { Log.observationFailed(error) }
    }

    /// Right under the title, like the Podcasts tab's: what goes here and a way to find it.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text("Nothing Here Yet")
                .font(theme.typography.title)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Pick albums from your library, or use Add to Collection on any album.")
                .font(theme.typography.body)
                .foregroundStyle(theme.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton("Add Albums", glyph: .add) { showPicker = true }
                .padding(.top, theme.spacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.screenInset)
        .padding(.top, theme.spacing.lg)
    }
}
