import DesignSystem
import Playback
import Podcasts
import SwiftUI

/// One episode: art, show, title, play, actions, chapters and show notes. Timestamps in the
/// notes start playback at that time.
struct EpisodeDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(AudioPlayer.self) private var player
    @Environment(\.pushPodcastRoute) private var push
    let episodeID: String
    @State private var item: EpisodeItem?
    @State private var notes: AttributedString?
    @State private var chapters: [Chapter] = []

    var body: some View {
        ScrollView {
            if let item {
                content(item)
            } else {
                LoadingMark().padding(.top, 120)
            }
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let item {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        EpisodeMenu(item: item)
                    } label: {
                        Label("More", glyph: .more)
                    }
                }
            }
        }
        // Show-notes links: timestamps seek; web links open in Safari (never in-app).
        .environment(\.openURL, OpenURLAction { url in
            if let seconds = ShowNotes.seekTime(url), let item {
                podcasts.play(item, from: seconds)
                return .handled
            }
            return .systemAction
        })
        .task { await observe() }
        .enableInjection()
    }

    private func observe() async {
        do {
            for try await value in podcasts.observe(podcasts.database.episode(id: episodeID)) {
                if value?.episode.notesHTML != item?.episode.notesHTML, let html = value?.episode.notesHTML {
                    notes = await Self.renderNotes(html)
                }
                if item == nil, let value {
                    item = value
                    Task { chapters = await ChapterLoader.load(chaptersURL: value.episode.chaptersURL, audioURL: podcasts.localFile(episodeID: value.id) ?? value.episode.audioURL) }
                }
                item = value
            }
        } catch { Log.observationFailed(error) }
    }

    /// Sanitizing long notes is string work; keep it off the main actor.
    @concurrent private static func renderNotes(_ html: String) async -> AttributedString {
        ShowNotes.attributed(html: html)
    }

    private func content(_ item: EpisodeItem) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center, spacing: theme.spacing.md) {
                ArtworkView(.unsized(item.artworkURL, maxPixelWidth: 720), cornerRadius: theme.radius.small)
                    .frame(width: 200)
                    .shadow(color: .black.opacity(theme.artwork.shadowOpacity), radius: theme.artwork.shadowRadius, y: 4)
                    .frame(maxWidth: .infinity)
                Button { push(.show(ShowRoute(item.show))) } label: {
                    Text(item.show.title)
                        .font(theme.typography.itemTitle)
                        .foregroundStyle(theme.palette.accent)
                        .textCase(.uppercase)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the podcast")
                Text(item.episode.title)
                    .font(theme.typography.title)
                    .tracking(theme.typography.displayTracking)
                    .foregroundStyle(theme.palette.textPrimary)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .center)
                    .accessibilityAddTraits(.isHeader)
                Text(metadata(item))
                    .font(BrandFont.font(.footnote))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: theme.spacing.md) {
                PrimaryButton(playTitle(item)) {
                    if player.current?.trackID == item.id { player.togglePlayPause() } else { podcasts.play(item) }
                }
                if item.episode.isInProgress {
                    ProgressView(value: item.episode.progress)
                        .tint(theme.palette.accent)
                        .accessibilityLabel("Listened")
                        .accessibilityValue(Text(item.episode.progress, format: .percent.precision(.fractionLength(0))))
                }
                actions(item)
            }

            if !chapters.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Chapters")
                        .font(theme.typography.sectionHeader)
                        .foregroundStyle(theme.palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, theme.spacing.sm)
                    ForEach(chapters) { chapter in
                        Button { podcasts.play(item, from: chapter.start) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.md) {
                                Text(Duration.seconds(chapter.start), format: .time(pattern: chapter.start >= 3600 ? .hourMinuteSecond : .minuteSecond))
                                    .font(theme.typography.caption.monospacedDigit())
                                    .foregroundStyle(theme.palette.textSecondary)
                                    .frame(minWidth: 52, alignment: .leading)
                                Text(chapter.title)
                                    .font(theme.typography.body)
                                    .foregroundStyle(theme.palette.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, theme.spacing.sm)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(theme.palette.separator)
                    }
                }
            }

            if let notes, !notes.characters.isEmpty {
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    Text("Show Notes")
                        .font(theme.typography.sectionHeader)
                        .foregroundStyle(theme.palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(notes)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.palette.textPrimary)
                        .tint(theme.palette.accent)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, theme.spacing.screenInset)
        .padding(.vertical, theme.spacing.lg)
    }

    private func actions(_ item: EpisodeItem) -> some View {
        HStack {
            actionButton(item.episode.isSaved ? "Saved" : "Save", glyph: item.episode.isSaved ? .saved : .save) {
                podcasts.setSaved(item.id, !item.episode.isSaved)
            }
            Spacer()
            downloadAction(item)
            Spacer()
            actionButton("Play Next", glyph: .playNext) { podcasts.playNext(item) }
            Spacer()
            actionButton(item.episode.isPlayed ? "Unplayed" : "Played", glyph: .check) {
                podcasts.setPlayed([item.id], !item.episode.isPlayed)
            }
        }
        .padding(.horizontal, theme.spacing.sm)
    }

    @ViewBuilder private func downloadAction(_ item: EpisodeItem) -> some View {
        switch podcasts.downloadStates[item.id]?.state {
        case .done?:
            actionButton("Downloaded", glyph: .downloaded) { podcasts.removeDownload(item.id) }
                .accessibilityHint("Removes the download")
        case .queued?, .downloading?:
            Button { podcasts.removeDownload(item.id) } label: {
                VStack(spacing: theme.spacing.xs) {
                    ProgressRing(progress: podcasts.downloadStates[item.id]?.progress ?? 0).frame(width: 22, height: 22)
                    Text("Cancel").font(theme.typography.caption)
                }
                .foregroundStyle(theme.palette.textPrimary)
                .frame(minWidth: 64, minHeight: 44)
            }
            .buttonStyle(.plain)
        case .failed?, nil:
            actionButton("Download", glyph: .download) { podcasts.download(item) }
        }
    }

    private func actionButton(_ title: String, glyph: Glyph, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: theme.spacing.xs) {
                glyph.image.foregroundStyle(theme.palette.accent)
                Text(title).font(theme.typography.caption)
            }
            .foregroundStyle(theme.palette.textPrimary)
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }

    private func playTitle(_ item: EpisodeItem) -> LocalizedStringKey {
        if player.current?.trackID == item.id { return player.isPlaying ? "Pause" : "Resume" }
        return item.episode.isInProgress ? "Resume" : "Play"
    }

    private func metadata(_ item: EpisodeItem) -> String {
        var parts = [EpisodeFormat.date(item.episode.publishedAt)]
        if let season = item.episode.season, let number = item.episode.number {
            parts.append("S\(season) E\(number)")
        } else if let number = item.episode.number {
            parts.append("Episode \(number)")
        }
        parts.append(EpisodeFormat.status(item.episode))
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
