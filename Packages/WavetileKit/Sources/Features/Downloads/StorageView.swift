import DesignSystem
import Persistence
import Podcasts
import SwiftUI

/// What's taking up space: every download with its size, removable in place, singly (swipe),
/// in bulk (Select) or by rule (played episodes), largest first. Opened from Storage Used in the profile
/// drawer and from the Downloads overflow menu.
struct StorageView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadsStore.self) private var downloads
    @Environment(PodcastsStore.self) private var podcasts
    @State private var collections: [DownloadedCollection] = []
    @State private var episodes: [EpisodeItem] = []
    @State private var editMode: EditMode = .inactive
    /// Selected rows, as `m:<collection id>` or `p:<episode id>`.
    @State private var selection: Set<String> = []
    @State private var confirmRemoveSelected = false
    @State private var confirmRemovePlayed = false
    @State private var freeBytes: Int64?

    private var music: [DownloadedCollection] {
        collections.filter { $0.bytes > 0 || $0.status.isRequested }.sorted { $0.bytes > $1.bytes }
    }

    /// Empty with podcasts off: their downloads stay on disk but are out of sight here.
    private var finishedEpisodes: [EpisodeItem] {
        guard podcasts.isEnabled else { return [] }
        return episodes.filter { $0.download?.state == .done }.sorted { ($0.download?.bytes ?? 0) > ($1.download?.bytes ?? 0) }
    }

    /// Played episodes that aren't saved: what "Remove played downloads" would clear.
    private var playedEpisodes: [EpisodeItem] {
        finishedEpisodes.filter { $0.episode.isPlayed && !$0.episode.isSaved }
    }

    private var isEditing: Bool { editMode.isEditing }

    /// The selection minus rows that have since gone, so counts and removal never act on stale ones.
    private var chosen: Set<String> {
        selection.intersection(music.map { "m:\($0.collection.id)" } + finishedEpisodes.map { "p:\($0.id)" })
    }

    var body: some View {
        NavigationStack {
            SettingsForm(selection: $selection) {
                summarySection
                if music.isEmpty, finishedEpisodes.isEmpty {
                    Section { Text("Nothing downloaded").foregroundStyle(theme.palette.textSecondary) }
                }
                if !music.isEmpty {
                    Section("Music") {
                        ForEach(music) { item in
                            row(
                                title: item.collection.name,
                                subtitle: item.collection.subtitle,
                                bytes: item.bytes > 0 ? item.bytes : nil,
                                artwork: library.artwork(for: item.collection, maxPixelWidth: 120),
                                tag: "m:\(item.collection.id)"
                            ) { downloads.remove(collectionID: item.collection.id) }
                        }
                    }
                }
                if !finishedEpisodes.isEmpty {
                    Section("Podcasts") {
                        ForEach(finishedEpisodes) { item in
                            row(
                                title: item.episode.title,
                                subtitle: item.show.title,
                                bytes: item.download?.bytes,
                                artwork: .unsized(item.artworkURL, maxPixelWidth: 120),
                                tag: "p:\(item.id)"
                            ) { podcasts.removeDownload(item.id) }
                        }
                        if !playedEpisodes.isEmpty {
                            Button { confirmRemovePlayed = true } label: {
                                Label("Remove Played Episodes (\(Self.size(playedBytes)))", glyph: .trash)
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !(music.isEmpty && finishedEpisodes.isEmpty) {
                    TintedSheetButton(isEditing ? "Cancel" : "Select", glyph: isEditing ? .close : .edit, placement: .cancellationAction) {
                        withAnimation(theme.motion.smooth) {
                            editMode = isEditing ? .inactive : .active
                            selection = []
                        }
                    }
                }
                TintedSheetButton("Done", glyph: .check, placement: .confirmationAction) { dismiss() }
                if isEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Remove \(chosen.count) Selected", role: .destructive) { confirmRemoveSelected = true }
                            .disabled(chosen.isEmpty)
                    }
                }
            }
            .confirmationDialog("Remove \(chosen.count) selected downloads?", isPresented: $confirmRemoveSelected, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { removeSelected() }
            } message: { Text("You can download them again anytime.") }
            .confirmationDialog("Remove \(playedEpisodes.count) played episodes?", isPresented: $confirmRemovePlayed, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { for item in playedEpisodes { podcasts.removeDownload(item.id) } }
            } message: { Text("Saved episodes are kept.") }
            .tintedSystemBack()
            // Files go a moment after their rows do, so wait before re-reading free space.
            .task(id: downloads.totalBytes + podcasts.totalBytes) {
                try? await Task.sleep(for: .milliseconds(600))
                freeBytes = Self.freeSpace()
            }
            .task {
                do {
                    for try await value in library.observe(library.database.downloadedCollections()) {
                        withAnimation(theme.motion.smooth) { collections = value }
                    }
                } catch { Log.observationFailed(error) }
            }
            .task {
                do {
                    for try await value in podcasts.observe(podcasts.database.downloads()) {
                        withAnimation(theme.motion.smooth) { episodes = value }
                    }
                } catch { Log.observationFailed(error) }
            }
        }
    }

    // MARK: Summary

    private var playedBytes: Int64 { playedEpisodes.reduce(0) { $0 + ($1.download?.bytes ?? 0) } }

    /// Not rows (nothing here is tappable): three figures side by side.
    private var summarySection: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: theme.spacing.sm) { stats }
                VStack(spacing: theme.spacing.sm) { stats }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder private var stats: some View {
        stat("Music", downloads.totalBytes)
        if podcasts.isEnabled { stat("Podcasts", podcasts.totalBytes) }
        if let freeBytes { stat("Free", freeBytes) }
    }

    private func stat(_ title: String, _ bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(title)
                .font(theme.typography.caption)
                .foregroundStyle(theme.palette.textSecondary)
            Text(Self.size(bytes))
                .font(theme.typography.mono(.callout))
                .foregroundStyle(theme.palette.textPrimary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.surface, in: .rect(cornerRadius: theme.radius.card))
        .accessibilityElement(children: .combine)
    }

    // MARK: Rows

    @ViewBuilder
    private func row(title: String, subtitle: String, bytes: Int64?, artwork: ArtworkSource, tag: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: theme.spacing.md) {
            ArtworkView(artwork, cornerRadius: theme.radius.small)
                .frame(width: theme.artwork.rowThumbnail)
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(title).font(theme.typography.itemTitle).foregroundStyle(theme.palette.textPrimary)
                Text(subtitle).font(theme.typography.itemSubtitle).foregroundStyle(theme.palette.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: theme.spacing.sm)
            Text(bytes.map(Self.size) ?? "Pending")
                .font(theme.typography.itemMetadata)
                .foregroundStyle(theme.palette.textSecondary)
        }
        .tag(tag)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Remove", glyph: .trash, role: .destructive, action: remove)
        }
        .contextMenu {
            Button("Remove Download", glyph: .trash, role: .destructive, action: remove)
        }
    }

    private func removeSelected() {
        for tag in chosen {
            if tag.hasPrefix("m:") { downloads.remove(collectionID: String(tag.dropFirst(2))) }
            else if tag.hasPrefix("p:") { podcasts.removeDownload(String(tag.dropFirst(2))) }
        }
        selection = []
        withAnimation(theme.motion.smooth) { editMode = .inactive }
    }

    static func size(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    /// Space iOS reports as available for important data (counts purgeable space).
    private static func freeSpace() -> Int64? {
        let values = try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
