import DesignSystem
import Library
import Persistence
import SwiftUI

/// Pick songs for a playlist or albums for a collection without leaving it: the whole library,
/// narrowed by search, tap to select, then one Add sends them all. Opened from an empty
/// playlist or collection's call to action.
struct LibraryPicker: View {
    enum Target {
        case playlist(id: String)
        case collection(id: String)
    }

    private struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let artwork: ArtworkSource
    }

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    let target: Target
    @State private var all: [Item] = []
    @State private var results: [Item]?
    @State private var text = ""
    /// In tap order, so songs land in the playlist in the order they were picked.
    @State private var picked: [String] = []
    @State private var isAdding = false

    private var isSongs: Bool { if case .playlist = target { true } else { false } }
    private var noun: String { isSongs ? (picked.count == 1 ? "Song" : "Songs") : (picked.count == 1 ? "Album" : "Albums") }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    rows(results ?? all)
                } header: {
                    if results == nil, !all.isEmpty {
                        Text("Recently Added")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: isSongs ? "Search all songs" : "Search all albums")
            .overlay {
                if let results, results.isEmpty, !text.isEmpty {
                    EmptyState("No Results", message: "Try another name or artist.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !picked.isEmpty {
                    PrimaryButton("Add \(picked.count) \(noun)", glyph: .add) { add() }
                        .disabled(isAdding)
                        .padding(.horizontal, theme.spacing.screenInset)
                        .padding(.bottom, theme.spacing.md)
                }
            }
            .navigationTitle(isSongs ? "Add Songs" : "Add Albums")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                TintedSheetButton("Cancel", glyph: .close, placement: .cancellationAction) { dismiss() }
            }
            // Brand bar titles and the tinted Back (SwiftUI's own bar appearances ignore the proxy).
            .tintedSystemBack()
        }
        .task { await load() }
        .task(id: text) { await search() }
    }

    private func rows(_ items: [Item]) -> some View {
        ForEach(items) { item in
            Button { toggle(item.id) } label: {
                HStack(spacing: theme.spacing.md) {
                    TrackRow(title: item.title, subtitle: item.subtitle, leading: .artwork(item.artwork))
                    if picked.contains(item.id) {
                        Glyph.check.image.foregroundStyle(theme.palette.accent)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowBackground(picked.contains(item.id) ? theme.palette.tint : Color.clear)
            .accessibilityAddTraits(picked.contains(item.id) ? .isSelected : [])
        }
    }

    private func toggle(_ id: String) {
        if let index = picked.firstIndex(of: id) { picked.remove(at: index) } else { picked.append(id) }
    }

    /// Before a search: the newest additions, a short list read off the main thread, so the
    /// sheet opens instantly however big the library is. Search reaches everything else.
    private func load() async {
        do {
            all = isSongs
                ? try await store.database.recentlyAddedTracks().map(item)
                : try await store.database.recentlyAddedAlbumList().map(item)
        } catch { Log.observationFailed(error) }
    }

    /// The library's full-text search, debounced while typing.
    private func search() async {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { results = nil; return }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled, let found = try? await store.database.search(query, limit: 200) else { return }
        results = isSongs ? found.tracks.map(item) : found.albums.map(item)
    }

    private func item(_ track: TrackRecord) -> Item {
        Item(id: track.id, title: track.title, subtitle: track.artistName,
             artwork: store.artwork(itemID: track.albumID, tag: track.albumImageTag, maxPixelWidth: 144))
    }

    private func item(_ album: AlbumRecord) -> Item {
        Item(id: album.id, title: album.title, subtitle: album.artistName,
             artwork: store.artwork(itemID: album.id, tag: album.imageTag, maxPixelWidth: 144))
    }

    private func add() {
        isAdding = true
        let ids = picked, label = "Added \(ids.count) \(noun.lowercased())"
        Task {
            do {
                switch target {
                case let .playlist(id): try await store.editor.addToPlaylist(id: id, trackIDs: ids)
                case let .collection(id): try await store.editor.addToCollection(id: id, albumIDs: ids)
                }
                actions.confirm(label)
                dismiss()
            } catch {
                Log.editFailed(isSongs ? "Add songs" : "Add albums", error)
                actions.errorMessage = "Couldn't add them. Check your connection."
                isAdding = false
            }
        }
    }
}
