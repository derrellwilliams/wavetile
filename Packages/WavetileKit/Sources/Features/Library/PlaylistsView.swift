import DesignSystem
import Library
import Persistence
import Playback
import SwiftUI

/// Song-based playlists: create, delete, open.
struct PlaylistsView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    @State private var playlists: [PlaylistRecord] = []
    @State private var showNew = false
    @State private var newName = ""
    @State private var pendingDelete: PlaylistRecord?

    var body: some View {
        List {
            ForEach(playlists) { playlist in
                NavigationLink(value: LibraryRoute.playlist(playlist)) {
                    HStack(spacing: theme.spacing.md) {
                        ArtworkView(store.artwork(itemID: playlist.id, tag: playlist.imageTag, maxPixelWidth: 192))
                            .frame(width: 56)
                        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                            Text(playlist.name)
                                .font(theme.typography.body)
                                .foregroundStyle(theme.palette.textPrimary)
                            Text("\(playlist.trackCount) songs")
                                .font(theme.typography.itemSubtitle)
                                .foregroundStyle(theme.palette.textSecondary)
                        }
                        .lineLimit(1)
                    }
                }
                .listRowBackground(Color.clear)
                .swipeActions {
                    Button("Delete", role: .destructive) { pendingDelete = playlist }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if playlists.isEmpty {
                if store.hasSyncedOnce {
                    EmptyState("No Playlists", glyph: .playlist, message: "Tap + to create one, or long-press any song and choose “Add to Playlist”.")
                } else {
                    LibraryEmptyState()
                }
            }
        }
        .themedBackground()
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Playlist", glyph: .add) { showNew = true }
            }
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
                        actions.errorMessage = "Couldn't create the playlist. Check your connection."
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
                        actions.errorMessage = "Couldn't delete the playlist."
                    }
                }
            }
        } message: {
            Text("This deletes it from your Jellyfin server for all your devices.")
        }
        .task {
            do {
                for try await value in store.observe(store.database.playlists()) { playlists = value }
            } catch {}
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
    @State private var showRename = false
    @State private var newName = ""
    @State private var showEditor = false
    @State private var confirmDelete = false

    init(playlist: PlaylistRecord) {
        _playlist = State(initialValue: playlist)
    }

    private var artwork: ArtworkSource {
        store.artwork(itemID: playlist.id, tag: playlist.imageTag, maxPixelWidth: 1320)
    }

    private var tracks: [TrackRecord] { items.map(\.track) }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.xl) {
                VStack(spacing: theme.spacing.md) {
                    ArtworkHero(artwork: artwork)
                    VStack(spacing: theme.spacing.xs) {
                        Text(playlist.name)
                            .font(theme.typography.title)
                            .foregroundStyle(theme.palette.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("\(playlist.trackCount) songs · \(Duration.milliseconds(playlist.durationMs).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.palette.textSecondary)
                        DownloadButton(collectionID: playlist.id) {
                            downloads.download(playlist: playlist, trackIDs: tracks.map(\.id), albumIDs: tracks.compactMap(\.albumID))
                        }
                        .padding(.top, theme.spacing.sm)
                        .disabled(items.isEmpty)
                    }
                    .padding(.horizontal, theme.spacing.screenInset)
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let track = item.track
                        PlayableRow(trackID: track.id, index: index, tracks: { tracks.map(QueuedTrack.init) }) {
                            TrackRow(
                                title: track.title,
                                subtitle: track.artistName,
                                duration: track.durationMs.map { .milliseconds($0) },
                                leading: .artwork(store.artwork(itemID: track.albumID, maxPixelWidth: 144)),
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
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        // Full-bleed art: no dimming/blur band under the navigation bar.
        .scrollEdgeEffectHidden(true, for: .top)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename", glyph: .edit) {
                        newName = playlist.name
                        showRename = true
                    }
                    Button("Edit Songs", glyph: .playlist) { showEditor = true }
                        .disabled(items.isEmpty)
                    Divider()
                    Button("Delete Playlist", glyph: .trash, role: .destructive) { confirmDelete = true }
                } label: {
                    Label("More", glyph: .more)
                }
            }
        }
        .alert("Rename Playlist", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name != playlist.name else { return }
                run("Couldn't rename the playlist.") { try await store.editor.renamePlaylist(id: playlist.id, to: name) }
            }
        }
        .confirmationDialog("Delete “\(playlist.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) {
                Task {
                    do {
                        try await store.editor.deletePlaylist(id: playlist.id)
                        dismiss()
                    } catch {
                        actions.errorMessage = "Couldn't delete the playlist."
                    }
                }
            }
        } message: {
            Text("This deletes it from your Jellyfin server for all your devices.")
        }
        .sheet(isPresented: $showEditor) {
            PlaylistEditor(playlistID: playlist.id, items: items)
                .presentationBackground(theme.palette.background)
        }
        .task { await observe() }
        .enableInjection()
    }

    private func run(_ failure: String, _ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { actions.errorMessage = failure }
        }
    }

    private func observe() async {
        async let items: Void = observeItems()
        async let record: Void = observeRecord()
        _ = await (items, record)
    }

    private func observeItems() async {
        do {
            for try await value in store.observe(store.database.playlistItems(playlistID: playlist.id)) { items = value }
        } catch {}
    }

    private func observeRecord() async {
        do {
            for try await value in store.observe(store.database.playlistObservation(id: playlist.id)) {
                if let value { playlist = value }
            }
        } catch {}
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
                        leading: .artwork(store.artwork(itemID: item.track.albumID, maxPixelWidth: 144))
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", glyph: .check) { dismiss() }
                }
            }
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
                actions.errorMessage = "Couldn't reorder the playlist."
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let entryIDs = offsets.compactMap { items[$0].entry.entryID }
        items.remove(atOffsets: offsets)
        Task {
            do { try await store.editor.removeFromPlaylist(id: playlistID, entryIDs: entryIDs) } catch {
                actions.errorMessage = "Couldn't remove songs from the playlist."
            }
        }
    }
}
