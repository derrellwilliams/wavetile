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

    /// A short-lived "it worked" banner for actions that otherwise give no visible result.
    struct Confirmation: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    var addToPlaylist: TrackSelection?
    var addToCollection: AlbumSelection?
    var errorMessage: String?
    private(set) var confirmation: Confirmation?

    func confirm(_ message: String) {
        let shown = Confirmation(message: message)
        confirmation = shown
        AccessibilityNotification.Announcement(message).post()
        Task {
            try? await Task.sleep(for: .seconds(2))
            if confirmation?.id == shown.id { confirmation = nil }
        }
    }

    /// Favorite from a menu, where (unlike the heart button) nothing on screen changes.
    func favorite(_ itemID: String, store: LibraryStore) {
        Task {
            do {
                try await store.editor.setFavorite(itemID: itemID, true)
                confirm("Added to Favorites")
            } catch {
                errorMessage = "Couldn't update favorites. Check your connection."
            }
        }
    }

    func addToPlaylist(_ trackIDs: [String]) { addToPlaylist = TrackSelection(trackIDs: trackIDs) }

    /// Songs a sheet wants to add to a playlist once it has dismissed (one sheet can't present
    /// over another that's leaving). The presenter calls `presentPending()` from `onDismiss`.
    var pendingPlaylistTrackIDs: [String]?

    func presentPending() {
        guard let ids = pendingPlaylistTrackIDs else { return }
        pendingPlaylistTrackIDs = nil
        addToPlaylist(ids)
    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // Slides in from the top and leaves the same way.
            .overlay(alignment: .top) {
                if let confirmation = actions.confirmation {
                    ConfirmationBanner(message: confirmation.message)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(theme.motion.smooth, value: actions.confirmation)
            .sensoryFeedback(.success, trigger: actions.confirmation) { _, new in new != nil }
            .alert("Something Went Wrong", isPresented: Binding(get: { actions.errorMessage != nil }, set: { if !$0 { actions.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actions.errorMessage ?? "")
            }
    }
}

/// Glass capsule with a check and a short message, shown below the status bar.
private struct ConfirmationBanner: View {
    @Environment(\.theme) private var theme
    let message: String

    var body: some View {
        Label(message, glyph: .check)
            .labelStyle(.tintedIcon)
            .font(theme.typography.itemTitle)
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.md)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, theme.spacing.sm)
            .allowsHitTesting(false)
            .accessibilityHidden(true)  // Announced when shown instead.
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
        .foregroundStyle(theme.palette.accent)
        .contentTransition(.symbolEffect(.replace))
        .sensoryFeedback(.impact(weight: .light), trigger: isFavorite)
        .task(id: itemID) {
            do {
                for try await value in store.observe(store.database.isFavorite(itemID: itemID)) {
                    withAnimation(theme.motion.snappy) { isFavorite = value }
                }
            } catch { Log.observationFailed(error) }
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
                        .labelStyle(.tintedIcon)
                }
                .listRowBackground(Color.clear)
                ForEach(playlists) { playlist in
                    Button {
                        perform("Added to \(playlist.name)") { try await store.editor.addToPlaylist(id: playlist.id, trackIDs: trackIDs) }
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
                    perform("Created \(name)") { try await store.editor.createPlaylist(name: name, trackIDs: trackIDs) }
                }
            }
            .task {
                do {
                    for try await value in store.observe(store.database.playlists()) { playlists = value }
                } catch { Log.observationFailed(error) }
            }
        }
    }

    private func perform(_ success: String, _ work: @escaping () async throws -> Void) {
        dismiss()
        Task {
            do {
                try await work()
                actions.confirm(success)
            } catch { actions.errorMessage = "Couldn't update the playlist. Check your connection." }
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
                        .labelStyle(.tintedIcon)
                }
                .listRowBackground(Color.clear)
                ForEach(collections) { collection in
                    Button {
                        perform("Added to \(collection.name)") { try await store.editor.addToCollection(id: collection.id, albumIDs: albumIDs) }
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
                    perform("Created \(name)") { try await store.editor.createCollection(name: name, albumIDs: albumIDs) }
                }
            }
            .task {
                do {
                    for try await value in store.observe(store.database.collections()) { collections = value }
                } catch { Log.observationFailed(error) }
            }
        }
    }

    private func perform(_ success: String, _ work: @escaping () async throws -> Void) {
        dismiss()
        Task {
            do {
                try await work()
                actions.confirm(success)
            } catch { actions.errorMessage = "Couldn't update the collection. Check your connection." }
        }
    }
}
