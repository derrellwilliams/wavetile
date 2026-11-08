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
        collections.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
    }

    private var finishedEpisodes: [EpisodeItem] {
        episodes.filter { $0.download?.state == .done }.sorted { ($0.download?.bytes ?? 0) > ($1.download?.bytes ?? 0) }
    }

    /// Played episodes that aren't saved: what "Remove played downloads" would clear.
    private var playedEpisodes: [EpisodeItem] {
        finishedEpisodes.filter { $0.episode.isPlayed && !$0.episode.isSaved }
    }

    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        NavigationStack {
            SettingsForm(selection: isEditing ? $selection : nil) {
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
                                bytes: item.bytes,
                                artwork: library.artwork(for: item.collection, maxPixelWidth: 120),
                                tag: "m:\(item.id)"
                            ) { downloads.remove(collectionID: item.collection.id) }
                        }
                    }
                }
                if podcasts.isEnabled, !finishedEpisodes.isEmpty {
                    Section("Podcasts") {
                        ForEach(finishedEpisodes) { item in
                            row(
                                title: item.episode.title,
                                subtitle: item.show.title,
                                bytes: item.download?.bytes ?? 0,
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
                ToolbarItem(placement: .bottomBar) {
                    if isEditing {
                        Button("Remove \(selection.count) Selected", role: .destructive) { confirmRemoveSelected = true }
                            .disabled(selection.isEmpty)
                    }
                }
            }
            .confirmationDialog("Remove \(selection.count) selected downloads?", isPresented: $confirmRemoveSelected, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { removeSelected() }
            } message: { Text("You can download them again anytime.") }
            .confirmationDialog("Remove \(playedEpisodes.count) played episodes?", isPresented: $confirmRemovePlayed, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { for item in playedEpisodes { podcasts.removeDownload(item.id) } }
            } message: { Text("Saved episodes are kept.") }
            .tintedSystemBack()
            .task { freeBytes = Self.freeSpace() }
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

    private var summarySection: some View {
        Section {
            usageBar
            SettingsValue("Music", glyph: .downloads, value: Self.size(downloads.totalBytes))
            if podcasts.isEnabled {
                SettingsValue("Podcasts", glyph: .podcasts, value: Self.size(podcasts.totalBytes))
            }
            if let freeBytes {
                SettingsValue("Free on This iPhone", glyph: .address, value: Self.size(freeBytes))
            }
        }
    }

    /// Music against podcasts, as shares of what Wavetile stores (a whole-disk bar would hide
    /// downloads on a large device).
    private var usageBar: some View {
        let musicBytes = Double(downloads.totalBytes)
        let podcastBytes = podcasts.isEnabled ? Double(podcasts.totalBytes) : 0
        let total = max(musicBytes + podcastBytes, 1)
        return GeometryReader { proxy in
            HStack(spacing: 2) {
                Capsule().fill(theme.palette.accent)
                    .frame(width: proxy.size.width * musicBytes / total)
                Capsule().fill(theme.palette.accent.opacity(0.4))
            }
            .opacity(musicBytes + podcastBytes == 0 ? 0.2 : 1)
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    // MARK: Rows

    @ViewBuilder
    private func row(title: String, subtitle: String, bytes: Int64, artwork: ArtworkSource, tag: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: theme.spacing.md) {
            ArtworkView(artwork, cornerRadius: theme.radius.small)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(title).font(theme.typography.itemTitle).foregroundStyle(theme.palette.textPrimary)
                Text(subtitle).font(theme.typography.itemSubtitle).foregroundStyle(theme.palette.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: theme.spacing.sm)
            Text(Self.size(bytes))
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
        for tag in selection {
            if tag.hasPrefix("m:") { downloads.remove(collectionID: String(tag.dropFirst(2))) }
            else if tag.hasPrefix("p:") { podcasts.removeDownload(String(tag.dropFirst(2))) }
        }
        selection = []
        withAnimation(theme.motion.smooth) { editMode = .inactive }
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Space iOS reports as available for important data (counts purgeable space).
    private static func freeSpace() -> Int64? {
        let values = try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
