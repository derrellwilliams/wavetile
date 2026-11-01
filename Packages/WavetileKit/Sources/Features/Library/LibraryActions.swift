import DesignSystem
import Library
import Persistence
import Playback
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

    /// A short-lived banner: "it worked" for actions that otherwise give no visible result, or
    /// why something didn't play.
    struct Confirmation: Identifiable, Equatable {
        let id = UUID()
        let message: String
        var glyph: Glyph = .check
        var isWarning = false
    }

    var addToPlaylist: TrackSelection?
    var addToCollection: AlbumSelection?
    var errorMessage: String?
    private(set) var confirmation: Confirmation?

    func confirm(_ message: String) {
        show(Confirmation(message: message), for: .seconds(2))
    }

    /// Tried to play something that isn't downloaded while it can't stream.
    func showOffline() {
        let message = Connectivity.shared.hasNetwork
            ? "Can't reach your server. Download this while it's reachable to listen anywhere."
            : "You're offline. Download this when you're connected to listen anywhere."
        show(Confirmation(message: message, glyph: .offline, isWarning: true), for: .seconds(3.5))
    }

    private func show(_ shown: Confirmation, for duration: Duration) {
        confirmation = shown
        AccessibilityNotification.Announcement(shown.message).post()
        Task {
            try? await Task.sleep(for: duration)
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

    /// Radio from a song, album or artist: plays Jellyfin's Instant Mix for it.
    func startRadio(from itemID: String, store: LibraryStore, player: AudioPlayer) {
        Task {
            do {
                var queue = try await store.api.instantMix(itemID: itemID).compactMap { mix in
                    mix.album.map { QueuedTrack(mix.track, album: $0) }
                }
                // Instant Mix can pull from outside the synced music library; keep only songs here
                // (unless the first sync hasn't finished, when there's nothing to check against).
                if (try? store.database.isEmpty()) == false, let synced = try? store.database.trackIDs(in: queue.map(\.trackID)) {
                    queue.removeAll { !synced.contains($0.trackID) }
                }
                guard !queue.isEmpty else {
                    errorMessage = "Couldn't find songs to make a station from."
                    return
                }
                player.play(queue)
            } catch {
                errorMessage = "Couldn't start radio. Check your connection."
            }
        }
    }

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
                    ConfirmationBanner(confirmation: confirmation)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(theme.motion.smooth, value: actions.confirmation)
            .sensoryFeedback(trigger: actions.confirmation) { _, new in
                new.map { $0.isWarning ? .warning : .success }
            }
            .alert("Something Went Wrong", isPresented: Binding(get: { actions.errorMessage != nil }, set: { if !$0 { actions.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actions.errorMessage ?? "")
            }
    }
}

/// Glass capsule with an icon and a short message, shown below the status bar.
private struct ConfirmationBanner: View {
    @Environment(\.theme) private var theme
    let confirmation: LibraryActions.Confirmation

    var body: some View {
        Label(confirmation.message, glyph: confirmation.glyph)
            .labelStyle(.tintedIcon)
            .font(theme.typography.itemTitle)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.md)
            .glassEffect(.regular, in: .rect(cornerRadius: theme.radius.card))
            .padding(.horizontal, theme.spacing.screenInset)
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
    /// Nil in a navigation bar: a plain bar item, sized and tinted like its neighbours.
    var size: CGFloat?
    @State private var isFavorite = false

    var body: some View {
        button
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

    @ViewBuilder private var button: some View {
        let title = isFavorite ? "Unfavorite" : "Favorite"
        let glyph: Glyph = isFavorite ? .favoriteFilled : .favorite
        if let size {
            GlyphButton(title, glyph: glyph, size: size, action: toggle)
                .foregroundStyle(theme.palette.accent)
        } else {
            Button(title, glyph: glyph, action: toggle)
        }
    }

    private func toggle() {
        let target = !isFavorite
        Task {
            do { try await store.editor.setFavorite(itemID: itemID, target) } catch {
                actions.errorMessage = "Couldn't update favorites. Check your connection."
            }
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
                        .font(theme.typography.body)
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
                                    .font(theme.typography.itemMetadata)
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
                TintedSheetButton("Cancel", glyph: .close, placement: .cancellationAction) { dismiss() }
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
            // Brand bar titles and the tinted Back (SwiftUI's own bar appearances ignore the proxy).
            .tintedSystemBack()
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
                        .font(theme.typography.body)
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
                                    .font(theme.typography.itemMetadata)
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
                TintedSheetButton("Cancel", glyph: .close, placement: .cancellationAction) { dismiss() }
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
            // Brand bar titles and the tinted Back (SwiftUI's own bar appearances ignore the proxy).
            .tintedSystemBack()
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
