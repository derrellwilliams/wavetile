import DesignSystem
import Library
import Persistence
import SwiftUI

/// App-wide "add to…" flows, so any row or page can open them without owning a sheet.
@Observable
final class LibraryActions {
    struct TrackSelection: Identifiable {
        let id = UUID()
        let trackIDs: [String]
    }

    struct AlbumSelection: Identifiable {
        let id = UUID()
        let albumIDs: [String]
    }

    var addToPlaylist: TrackSelection?
    var addToCollection: AlbumSelection?
    var errorMessage: String?

    func addToPlaylist(_ trackIDs: [String]) { addToPlaylist = TrackSelection(trackIDs: trackIDs) }
    func addToCollection(_ albumIDs: [String]) { addToCollection = AlbumSelection(albumIDs: albumIDs) }
}

extension View {
    /// Attaches the add-to-playlist / add-to-collection sheets and error alert. Apply once at the root.
    func libraryActionSheets(_ actions: LibraryActions) -> some View {
        modifier(LibraryActionSheets(actions: actions))
    }
}

private struct LibraryActionSheets: ViewModifier {
    @Bindable var actions: LibraryActions
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.addToPlaylist) { selection in
                AddToPlaylistSheet(trackIDs: selection.trackIDs)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(theme.palette.background)
            }
            .sheet(item: $actions.addToCollection) { selection in
                AddToCollectionSheet(albumIDs: selection.albumIDs)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(theme.palette.background)
            }
            .alert("Something Went Wrong", isPresented: Binding(get: { actions.errorMessage != nil }, set: { if !$0 { actions.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actions.errorMessage ?? "")
            }
    }
}

/// Heart toggle for an album, artist, or track; reads the live flag from the database.
struct FavoriteButton: View {
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    let itemID: String
    var size: CGFloat = 24
    @State private var isFavorite = false

    var body: some View {
        GlyphButton(isFavorite ? "Unfavorite" : "Favorite", glyph: isFavorite ? .favoriteFilled : .favorite, size: size) {
            let target = !isFavorite
            Task {
                do { try await store.editor.setFavorite(itemID: itemID, target) } catch {
                    actions.errorMessage = "Couldn't update favorites. Check your connection."
                }
            }
        }
        .foregroundStyle(isFavorite ? theme.palette.accent : theme.palette.textPrimary)
        .contentTransition(.symbolEffect(.replace))
        .sensoryFeedback(.impact(weight: .light), trigger: isFavorite)
        .task(id: itemID) {
            do {
                for try await value in store.observe(store.database.isFavorite(itemID: itemID)) {
                    withAnimation(theme.motion.bouncy) { isFavorite = value }
                }
            } catch {}
        }
    }
}

/// Pick an existing playlist or create a new one with the selected songs.
struct AddToPlaylistSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    let trackIDs: [String]
    @State private var playlists: [PlaylistRecord] = []
    @State private var newName = ""
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Button { showNew = true } label: {
                    Label("New Playlist", glyph: .add)
                        .font(theme.typography.body.weight(.semibold))
                        .foregroundStyle(theme.palette.accent)
                }
                .listRowBackground(Color.clear)
                ForEach(playlists) { playlist in
                    Button {
                        perform { try await store.editor.addToPlaylist(id: playlist.id, trackIDs: trackIDs) }
                    } label: {
                        HStack(spacing: theme.spacing.md) {
                            ArtworkView(store.artwork(itemID: playlist.id, tag: playlist.imageTag, maxPixelWidth: 144))
                                .frame(width: theme.artwork.rowThumbnail)
                            VStack(alignment: .leading) {
                                Text(playlist.name).font(theme.typography.body)
                                Text("\(playlist.trackCount) songs")
                                    .font(theme.typography.itemSubtitle)
                                    .foregroundStyle(theme.palette.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle(trackIDs.count == 1 ? "Add to Playlist" : "Add \(trackIDs.count) Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("New Playlist", isPresented: $showNew) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    newName = ""
                    guard !name.isEmpty else { return }
                    perform { try await store.editor.createPlaylist(name: name, trackIDs: trackIDs) }
                }
            }
            .task {
                do {
                    for try await value in store.observe(store.database.playlists()) { playlists = value }
                } catch {}
            }
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        dismiss()
        Task {
            do { try await work() } catch { actions.errorMessage = "Couldn't update the playlist. Check your connection." }
        }
    }
}

/// Pick an existing collection or create a new one with the selected albums.
struct AddToCollectionSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    let albumIDs: [String]
    @State private var collections: [CollectionRecord] = []
    @State private var newName = ""
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Button { showNew = true } label: {
                    Label("New Collection", glyph: .add)
                        .font(theme.typography.body.weight(.semibold))
                        .foregroundStyle(theme.palette.accent)
                }
                .listRowBackground(Color.clear)
                ForEach(collections) { collection in
                    Button {
                        perform { try await store.editor.addToCollection(id: collection.id, albumIDs: albumIDs) }
                    } label: {
                        HStack(spacing: theme.spacing.md) {
                            CollectionMosaic(collectionID: collection.id)
                                .frame(width: theme.artwork.rowThumbnail)
                            VStack(alignment: .leading) {
                                Text(collection.name).font(theme.typography.body)
                                Text("\(collection.albumCount) albums")
                                    .font(theme.typography.itemSubtitle)
                                    .foregroundStyle(theme.palette.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("New Collection", isPresented: $showNew) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    newName = ""
                    guard !name.isEmpty else { return }
                    perform { try await store.editor.createCollection(name: name, albumIDs: albumIDs) }
                }
            }
            .task {
                do {
                    for try await value in store.observe(store.database.collections()) { collections = value }
                } catch {}
            }
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        dismiss()
        Task {
            do { try await work() } catch { actions.errorMessage = "Couldn't update the collection. Check your connection." }
        }
    }
}
