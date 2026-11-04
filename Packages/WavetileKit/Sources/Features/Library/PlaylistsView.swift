import DesignSystem
import Library
import Persistence
import Playback
import SwiftUI

/// Song-based playlists as a grid of covers, like Collections: create, delete, open.
struct PlaylistsView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    @State private var playlists: [PlaylistRecord] = []
    @State private var showNew = false
    @State private var newName = ""
    @State private var pendingDelete: PlaylistRecord?
    @State private var pickingCover: String?

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: theme.artwork.shelfTileWidth - 8), spacing: theme.spacing.lg)],
                alignment: .leading,
                spacing: theme.spacing.xl
            ) {
                ForEach(playlists) { playlist in
                    NavigationLink(value: LibraryRoute.playlist(playlist)) {
                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            ArtworkView(store.cover(for: playlist.id, tag: playlist.imageTag, maxPixelWidth: 480))
                            Text(playlist.name)
                                .font(theme.typography.itemTitle)
                                .foregroundStyle(theme.palette.textPrimary)
                            Text("\(playlist.trackCount) song\(playlist.trackCount == 1 ? "" : "s")")
                                .font(theme.typography.itemMetadata)
                                .foregroundStyle(theme.palette.textSecondary)
                        }
                        .lineLimit(1)
                    }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        CoverMenuItems(itemID: playlist.id, imageTag: playlist.imageTag, owner: .playlist, pickingCover: $pickingCover)
                        Button("Delete Playlist", glyph: .trash, role: .destructive) { pendingDelete = playlist }
                    }
                }
            }
            .padding(.horizontal, theme.spacing.screenInset)
            .padding(.vertical, theme.spacing.lg)
        }
        .overlay {
            if playlists.isEmpty {
                if store.hasSyncedOnce {
                    EmptyState("No Playlists", message: "Tap + to create one, or long-press any song and choose “Add to Playlist”.")
                } else {
                    LibraryEmptyState()
                }
            }
        }
        .themedBackground()
        .navigationTitle("Playlists")
        .coverImagePicker(itemID: $pickingCover, owner: .playlist)
        .listBar {
            Button { showNew = true } label: { TintedBarIcon(glyph: .add) }
                .accessibilityLabel("New Playlist")
        }
        .alert("New Playlist", isPresented: $showNew) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                newName = ""
                guard !name.isEmpty else { return }
                Task {
                    do { try await store.editor.createPlaylist(name: name) } catch {
                        actions.editFailed("create playlists", error)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive) {
                guard let playlist = pendingDelete else { return }
                Task {
                    do { try await store.editor.deletePlaylist(id: playlist.id) } catch {
                        actions.editFailed("delete this playlist", error)
                    }
                }
            }
        } message: {
            Text("This deletes it from your Jellyfin server for all your devices.")
        }
        .task {
            do {
                for try await value in store.observe(store.database.playlists()) { playlists = value }
            } catch { Log.observationFailed(error) }
        }
        .enableInjection()
    }
}

/// Playlist page: full-bleed artwork, name and stats, then tracks. Rename, edit, delete in the menu.
struct PlaylistDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadsStore.self) private var downloads
    @State private var playlist: PlaylistRecord
    @State private var items: [PlaylistItem] = []
    /// Set after the first read, so the empty state doesn't flash before the songs arrive.
    @State private var loaded = false
    @State private var showPicker = false
    @State private var showRename = false
    @State private var newName = ""
    @State private var showEditor = false
    @State private var confirmDelete = false
    @State private var pickingCover: String?

    init(playlist: PlaylistRecord) {
        _playlist = State(initialValue: playlist)
    }

    private var tracks: [TrackRecord] { items.map(\.track) }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.xl) {
                VStack(spacing: theme.spacing.md) {
                    ArtworkHero(artwork: store.cover(for: playlist.id, tag: playlist.imageTag, maxPixelWidth: 1320))
                    DetailHeader(playlist.name, metadata: "\(playlist.trackCount) songs · \(Duration.milliseconds(playlist.durationMs).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                }

                if loaded, items.isEmpty {
                    emptyState
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let track = item.track
                        PlayableRow(trackID: track.id, index: index, tracks: { tracks.map(QueuedTrack.init) }) {
                            TrackRow(
                                title: track.title,
                                subtitle: track.artistName,
                                duration: track.durationMs.map { .milliseconds($0) },
                                leading: .artwork(store.artwork(itemID: track.albumID, tag: track.albumImageTag, maxPixelWidth: 144)),
                                isPlaying: player.current?.trackID == track.id,
                                isDownloaded: downloads.isDownloaded(track.id)
                            )
                            .padding(.horizontal, theme.spacing.screenInset)
                            .padding(.vertical, theme.spacing.sm)
                        }
                    }
                }
            }
            .padding(.bottom, theme.spacing.xxl)
        }
        // Full-bleed art: no bar background or blur band under the navigation bar.
        .detailPageChrome()
        .detailBarButtons {
            DownloadButton(collectionID: playlist.id) {
                downloads.download(playlist: playlist, trackIDs: tracks.map(\.id), albumIDs: tracks.compactMap(\.albumID))
            }
            .disabled(items.isEmpty)
            Menu {
                Button("Rename", glyph: .edit) {
                    newName = playlist.name
                    showRename = true
                }
                CoverMenuItems(itemID: playlist.id, imageTag: playlist.imageTag, owner: .playlist, pickingCover: $pickingCover)
                Button("Edit Songs", glyph: .playlist) { showEditor = true }
                    .disabled(items.isEmpty)
                Divider()
                Button("Delete Playlist", glyph: .trash, role: .destructive) { confirmDelete = true }
            } label: {
                TintedBarIcon(glyph: .more)
            }
            .accessibilityLabel("More")
        }
        .alert("Rename Playlist", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name != playlist.name else { return }
                run("rename this playlist") { try await store.editor.renamePlaylist(id: playlist.id, to: name) }
            }
        }
        .confirmationDialog("Delete “\(playlist.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) {
                Task {
                    do {
                        try await store.editor.deletePlaylist(id: playlist.id)
                        dismiss()
                    } catch {
                        actions.editFailed("delete this playlist", error)
                    }
                }
            }
        } message: {
            Text("This deletes it from your Jellyfin server for all your devices.")
        }
        .coverImagePicker(itemID: $pickingCover, owner: .playlist)
        .sheet(isPresented: $showPicker) {
            LibraryPicker(target: .playlist(id: playlist.id))
                .presentationBackground(theme.palette.background)
        }
        .sheet(isPresented: $showEditor) {
            PlaylistEditor(playlistID: playlist.id, items: items)
                .presentationBackground(theme.palette.background)
        }
        .task { await observe() }
        .enableInjection()
    }

    /// `action` completes the failure message ("Couldn't rename this playlist", or the ask-your-admin one).
    private func run(_ action: String, _ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { actions.editFailed(action, error) }
        }
    }

    /// Under the header, like an empty collection's: what goes here and a way to add it.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text("Nothing Here Yet")
                .font(theme.typography.title)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Pick songs from your library, or long-press any song and choose Add to Playlist.")
                .font(theme.typography.body)
                .foregroundStyle(theme.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton("Add Songs", glyph: .add) { showPicker = true }
                .padding(.top, theme.spacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.screenInset)
    }

    private func observe() async {
        async let items: Void = observeItems()
        async let record: Void = observeRecord()
        _ = await (items, record)
    }

    private func observeItems() async {
        do {
            for try await value in store.observe(store.database.playlistItems(playlistID: playlist.id)) {
                items = value
                loaded = true
            }
        } catch { Log.observationFailed(error) }
    }

    private func observeRecord() async {
        do {
            for try await value in store.observe(store.database.playlistObservation(id: playlist.id)) {
                if let value { playlist = value }
            }
        } catch { Log.observationFailed(error) }
    }
}

/// Reorder (drag) and remove (swipe) songs. Each change is sent to the server right away.
private struct PlaylistEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    let playlistID: String
    @State var items: [PlaylistItem]

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    TrackRow(
                        title: item.track.title,
                        subtitle: item.track.artistName,
                        leading: .artwork(store.artwork(itemID: item.track.albumID, tag: item.track.albumImageTag, maxPixelWidth: 144))
                    )
                    .listRowBackground(Color.clear)
                }
                .onMove(perform: move)
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                TintedSheetButton("Done", glyph: .check, placement: .confirmationAction) { dismiss() }
            }
            // Brand bar titles and the tinted Back (SwiftUI's own bar appearances ignore the proxy).
            .tintedSystemBack()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        let item = items[from]
        items.move(fromOffsets: source, toOffset: destination)
        let newIndex = items.firstIndex(of: item) ?? 0
        guard let entryID = item.entry.entryID else { return }
        Task {
            do { try await store.editor.movePlaylistEntry(id: playlistID, entryID: entryID, to: newIndex) } catch {
                actions.editFailed("reorder this playlist", error)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let entryIDs = offsets.compactMap { items[$0].entry.entryID }
        items.remove(atOffsets: offsets)
        Task {
            do { try await store.editor.removeFromPlaylist(id: playlistID, entryIDs: entryIDs) } catch {
                actions.editFailed("remove songs from this playlist", error)
            }
        }
    }
}
