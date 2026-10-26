import DesignSystem
import Playback
import Podcasts
import SwiftUI

/// One episode, laid out like an album: hero art, title, show, play, show notes and chapters,
/// with Download, Save and More in the toolbar. Timestamps in the notes start playback there.
struct EpisodeDetailView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(AudioPlayer.self) private var player
    @Environment(\.pushPodcastRoute) private var push
    let episodeID: String
    @State private var item: EpisodeItem?
    @State private var notes: AttributedString?
    /// The notes as shown: without their timestamp list when the chapters list covers it.
    @State private var visibleNotes: AttributedString?
    /// The first paragraph, when the notes run longer; nil when they're one paragraph.
    @State private var notesPreview: AttributedString?
    @State private var notesExpanded = false
    @State private var chapters: [Chapter] = []

    var body: some View {
        ScrollView {
            if let item {
                content(item)
            } else {
                LoadingMark().padding(.top, 120)
            }
        }
        .detailPageChrome()
        .toolbar {
            if let item {
                ToolbarItem(placement: .topBarTrailing) {
                    EpisodeDownloadButton(item: item)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SaveEpisodeButton(episodeID: item.id)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        EpisodeMenu(item: item, includeGoToShow: false)
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
        // Structured: tied to the page, cancelled when it closes. Keyed by the episode, so
        // progress updates to `item` don't reload.
        .task(id: item?.id) {
            guard let episode = item?.episode else { return }
            let loaded = await podcasts.chapters(for: episode)
            guard !Task.isCancelled else { return }
            withAnimation(theme.motion.smooth) {
                chapters = loaded
                updateVisibleNotes()
            }
        }
        .enableInjection()
    }

    private func observe() async {
        do {
            for try await value in podcasts.observe(podcasts.database.episode(id: episodeID)) {
                if value?.episode.notesHTML != item?.episode.notesHTML, let html = value?.episode.notesHTML {
                    let rendered = await Self.renderNotes(html)
                    // Notes arrive after the page draws; ease them in rather than popping.
                    notes = rendered
                    withAnimation(theme.motion.smooth) { updateVisibleNotes() }
                }
                item = value
            }
        } catch { Log.observationFailed(error) }
    }

    /// Chapters are the tappable list, so the same timestamps aren't repeated in the notes.
    private func updateVisibleNotes() {
        guard let notes else { return }
        let visible = chapters.isEmpty ? notes : ShowNotes.removingTimestampLines(from: notes)
        visibleNotes = visible
        // Paragraphs are separated by a blank line; preview only when more text follows.
        if let breakRange = visible.range(of: "\n\n"),
           visible[breakRange.upperBound...].characters.contains(where: { !$0.isWhitespace }) {
            notesPreview = AttributedString(visible[..<breakRange.lowerBound])
        } else {
            notesPreview = nil
        }
    }

    /// Sanitizing long notes is string work; keep it off the main actor.
    @concurrent private static func renderNotes(_ html: String) async -> AttributedString {
        ShowNotes.attributed(html: html)
    }

    private func content(_ item: EpisodeItem) -> some View {
        VStack(spacing: theme.spacing.xl) {
            VStack(spacing: theme.spacing.md) {
                // A smaller square over a blur of the art; full-width show art read too big here.
                ArtworkSpotlight(artwork: .unsized(item.artworkURL, maxPixelWidth: 720))
                // Episode titles run far longer than album names, so they use the smaller title size.
                DetailHeader(item.episode.title, metadata: metadata(item), compact: true) {
                    Button { push(.show(ShowRoute(item.show))) } label: {
                        DetailSubtitle(item.show.title)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the podcast")
                }
            }

            VStack(alignment: .leading, spacing: theme.spacing.xl) {
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
                }

                if let visibleNotes, !visibleNotes.characters.isEmpty {
                    VStack(alignment: .leading, spacing: theme.spacing.sm) {
                        Text("Show Notes")
                            .font(theme.typography.sectionHeader)
                            .foregroundStyle(theme.palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(notesExpanded ? visibleNotes : notesPreview ?? visibleNotes)
                            .font(theme.typography.body)
                            .foregroundStyle(theme.palette.textPrimary)
                            .tint(theme.palette.accent)
                            .textSelection(.enabled)
                        if notesPreview != nil, !notesExpanded {
                            Button("Read More") {
                                withAnimation(theme.motion.smooth) { notesExpanded = true }
                            }
                            .font(theme.typography.itemSubtitle.weight(.semibold))
                            .foregroundStyle(theme.palette.accent)
                            .frame(minHeight: 44)
                            .accessibilityHint("Shows the full show notes")
                        }
                    }
                }

                if !chapters.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Chapters")
                            .font(theme.typography.sectionHeader)
                            .foregroundStyle(theme.palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, theme.spacing.sm)
                        // Highlights the chapter playing now when this episode is the one playing.
                        let current = player.current?.trackID == item.id ? chapters.current(at: player.currentTime) : nil
                        ForEach(chapters) { chapter in
                            ChapterRow(chapter: chapter, isCurrent: chapter == current, verticalPadding: theme.spacing.md) {
                                podcasts.play(item, from: chapter.start)
                            }
                            Divider().overlay(theme.palette.separator)
                        }
                    }
                }
            }
            .padding(.horizontal, theme.spacing.screenInset)
        }
        .padding(.bottom, theme.spacing.xxl)
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
