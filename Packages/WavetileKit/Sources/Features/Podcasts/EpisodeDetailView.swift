import DesignSystem
import Playback
import Podcasts
import SwiftUI

/// One episode, laid out like an album: hero art, title, show, play, show notes, chapters,
/// hosts and guests, and a transcript, with Download, Save and More in the toolbar. Timestamps in the notes start playback there.
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
    @State private var transcript: [TranscriptParagraph] = []
    @State private var showTranscript = false

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
        // Show-notes links: timestamps seek; web and mail links open in their apps (never in-app).
        // Notes come from the feed, so other schemes (tel:, sms:, other apps' links) are ignored.
        .environment(\.openURL, OpenURLAction { url in
            if let seconds = ShowNotes.seekTime(url), let item {
                podcasts.play(item, from: seconds)
                return .handled
            }
            switch url.scheme?.lowercased() {
            case "http", "https", "mailto": return .systemAction
            default: return .discarded
            }
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
        // Fetched from the podcast host when the page opens; the section only appears once it loads.
        .task(id: item?.episode.transcriptURL) {
            guard let episode = item?.episode, let url = episode.transcriptURL else { return }
            let loaded = (try? await Transcript.load(url: url, type: episode.transcriptType)) ?? []
            guard !Task.isCancelled else { return }
            withAnimation(theme.motion.smooth) { transcript = loaded }
        }
        .sheet(isPresented: $showTranscript) {
            if let item {
                TranscriptSheet(paragraphs: transcript) { podcasts.play(item, from: $0) }
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
    /// Links are underlined as well as colored: the accent is close to body text.
    @concurrent private static func renderNotes(_ html: String) async -> AttributedString {
        var notes = ShowNotes.attributed(html: html)
        let links = notes.runs.filter { $0.link != nil }.map(\.range)
        for range in links { notes[range].underlineStyle = .single }
        return notes
    }

    private func content(_ item: EpisodeItem) -> some View {
        VStack(spacing: theme.spacing.xl) {
            VStack(spacing: theme.spacing.md) {
                // A smaller square over a blur of the art; full-width show art read too big here.
                ArtworkSpotlight(artwork: .unsized(item.artworkURL, maxPixelWidth: 720))
                // Episode titles run far longer than album names, so they use the smaller text-face title.
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
                    PrimaryButton(playTitle(item), glyph: player.current?.trackID == item.id && player.isPlaying ? .pause : .play) {
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
                            .buttonStyle(.text)
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

                hostsAndGuests(item)

                if !transcript.isEmpty {
                    VStack(alignment: .leading, spacing: theme.spacing.sm) {
                        ShelfTitle("Transcript")
                        Text(transcript.prefix(3).map(\.text).joined(separator: "\n\n"))
                            .font(theme.typography.body)
                            .foregroundStyle(theme.palette.textPrimary)
                            .lineLimit(6)
                        Button("Read Transcript") { showTranscript = true }
                            .buttonStyle(.text)
                    }
                }
            }
            .padding(.horizontal, theme.spacing.screenInset)
        }
        .padding(.bottom, theme.spacing.xxl)
    }

    /// The episode's own hosts and guests, else the show's regular hosts.
    @ViewBuilder private func hostsAndGuests(_ item: EpisodeItem) -> some View {
        let people = item.episode.people.isEmpty ? item.show.people : item.episode.people
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                ShelfTitle(people.contains { $0.role != "host" } ? "Hosts & Guests" : "Hosts")
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: theme.spacing.lg) {
                        ForEach(people, id: \.self) { PersonView(person: $0) }
                    }
                }
                .scrollIndicators(.hidden)
                // Scrolls edge to edge while starting at the screen margin.
                .contentMargins(.horizontal, theme.spacing.screenInset, for: .scrollContent)
                .padding(.horizontal, -theme.spacing.screenInset)
            }
        }
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

/// A host or guest: round photo (or initials), name and role. Opens their page when the feed links one.
private struct PersonView: View {
    @Environment(\.theme) private var theme
    let person: PodcastPerson

    var body: some View {
        if let href = person.href {
            Link(destination: href) { content }
                .buttonStyle(.pressable)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: theme.spacing.xs) {
            Group {
                if let image = person.imageURL {
                    ArtworkView(.unsized(image, maxPixelWidth: 240))
                } else {
                    Text(initials)
                        .font(theme.typography.sectionHeader)
                        .foregroundStyle(theme.palette.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.palette.surface)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(.circle)
            Text(person.name)
                .font(theme.typography.itemSubtitle.weight(.semibold))
                .foregroundStyle(theme.palette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(person.role.capitalized)
                .font(theme.typography.caption)
                .foregroundStyle(theme.palette.textSecondary)
        }
        .frame(width: 96)
        .accessibilityElement(children: .combine)
    }

    private var initials: String {
        person.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

/// The full transcript. Timed paragraphs carry their start time; tapping it plays from there.
private struct TranscriptSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let paragraphs: [TranscriptParagraph]
    let seek: (Double) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.spacing.lg) {
                    ForEach(paragraphs) { paragraph in
                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            if paragraph.speaker != nil || paragraph.start != nil {
                                HStack(spacing: theme.spacing.sm) {
                                    if let start = paragraph.start {
                                        Button(Self.time(start)) { seek(start) }
                                            .buttonStyle(.tinted(.small))
                                            .accessibilityLabel("Play from \(Self.time(start))")
                                    }
                                    if let speaker = paragraph.speaker {
                                        Text(speaker)
                                            .font(theme.typography.caption.weight(.semibold))
                                            .foregroundStyle(theme.palette.textSecondary)
                                    }
                                }
                            }
                            Text(paragraph.text)
                                .font(theme.typography.body)
                                .foregroundStyle(theme.palette.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(theme.spacing.screenInset)
            }
            .themedBackground()
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Read-only, so it closes rather than confirms (Done is for finishing a task).
                ToolbarItem(placement: .cancellationAction) { Button("Close", glyph: .close) { dismiss() } }
            }
        }
        .presentationBackground(theme.palette.background)
    }

    private static func time(_ seconds: Double) -> String {
        let duration = Duration.seconds(seconds)
        return seconds >= 3600
            ? duration.formatted(.time(pattern: .hourMinuteSecond))
            : duration.formatted(.time(pattern: .minuteSecond))
    }
}
