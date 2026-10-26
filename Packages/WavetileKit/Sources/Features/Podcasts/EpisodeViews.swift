import DesignSystem
import Playback
import Podcasts
import SwiftUI

/// An episode in a list: date, title, summary, and a play pill with time left, like Apple
/// Podcasts. Tapping the row opens the episode; the pill plays or pauses it.
struct EpisodeRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pushPodcastRoute) private var push
    let item: EpisodeItem
    /// Hidden on the show's own page.
    var showsArtwork = true

    var body: some View {
        // A tap gesture, not a Button: the play pill and ⋯ menu inside must stay tappable.
        HStack(alignment: .top, spacing: theme.spacing.md) {
            if showsArtwork {
                ArtworkView(.unsized(item.artworkURL, maxPixelWidth: 168), cornerRadius: theme.radius.small)
                    .frame(width: 56)
            }
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(caption)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.palette.textSecondary)
                    .textCase(.uppercase)
                Text(item.episode.title)
                    .font(theme.typography.body.weight(.semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if !item.episode.summary.isEmpty {
                    Text(item.episode.summary)
                        .font(theme.typography.itemSubtitle)
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                }
                HStack(spacing: theme.spacing.sm) {
                    EpisodePlayButton(item: item)
                    EpisodeDownloadBadge(episodeID: item.id)
                    if item.episode.isSaved {
                        Glyph.saved.image
                            .resizable()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(theme.palette.accent)
                            .accessibilityLabel("Saved")
                    }
                    Spacer(minLength: 0)
                    EpisodeMenuButton(item: item)
                }
                .padding(.top, theme.spacing.xxs)
            }
            .multilineTextAlignment(.leading)
        }
        .padding(.vertical, theme.spacing.md)
        .contentShape(.rect)
        .onTapGesture { push(.episode(id: item.id)) }
        .opacity(item.episode.isPlayed ? 0.6 : 1)
        .contextMenu { EpisodeMenu(item: item) }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Show Episode") { push(.episode(id: item.id)) }
    }

    private var caption: String {
        let date = EpisodeFormat.date(item.episode.publishedAt)
        return showsArtwork ? [date, item.show.title].filter { !$0.isEmpty }.joined(separator: " · ") : date
    }
}

/// Play/pause pill with progress and time left.
struct EpisodePlayButton: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPlayer.self) private var player
    @Environment(PodcastsStore.self) private var podcasts
    let item: EpisodeItem
    @State private var taps = 0

    private var isCurrent: Bool { player.current?.trackID == item.id }
    private var isPlaying: Bool { isCurrent && player.isPlaying }

    var body: some View {
        Button {
            taps += 1
            if isCurrent { player.togglePlayPause() } else { podcasts.play(item) }
        } label: {
            HStack(spacing: theme.spacing.xs) {
                (isPlaying ? Glyph.pause : Glyph.play).image
                    .resizable()
                    .frame(width: 12, height: 12)
                if item.episode.isInProgress && !isCurrent {
                    ProgressView(value: item.episode.progress)
                        .progressViewStyle(.linear)
                        .tint(theme.palette.onAccent)
                        .frame(width: 28)
                }
                Text(isCurrent ? liveStatus : EpisodeFormat.status(item.episode))
                    .font(theme.typography.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(theme.palette.onAccent)
            .padding(.horizontal, theme.spacing.md)
            .frame(minHeight: 28)
            .background(theme.palette.accent, in: .capsule)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityValue(EpisodeFormat.status(item.episode))
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    private var liveStatus: String {
        guard player.duration > 0 else { return EpisodeFormat.status(item.episode) }
        return "\(EpisodeFormat.length(max(player.duration - player.currentTime, 0))) left"
    }
}

/// Small download state glyph: progress ring while downloading, check when done.
struct EpisodeDownloadBadge: View {
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    let episodeID: String

    var body: some View {
        if let record = podcasts.downloadStates[episodeID] {
            DownloadIcon(state: record.indicator, title: record.indicator.episodeTitle, size: 16)
                .foregroundStyle(theme.palette.textSecondary)
        }
    }
}

/// The episode page's toolbar download control, matching albums' `DownloadButton`:
/// download → progress ring (menu to cancel) → downloaded (menu to remove).
struct EpisodeDownloadButton: View {
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    let item: EpisodeItem

    private var indicator: DownloadIndicator { podcasts.downloadStates[item.id]?.indicator ?? .none }

    var body: some View {
        Group {
            switch indicator {
            case .done, .inProgress:
                Menu {
                    Button(indicator == .done ? "Remove Download" : "Cancel Download", glyph: indicator == .done ? .trash : .close, role: .destructive) {
                        podcasts.removeDownload(item.id)
                    }
                } label: {
                    DownloadIcon(state: indicator, title: indicator.episodeTitle)
                }
            case .none, .failed:
                Button { podcasts.download(item) } label: {
                    DownloadIcon(state: indicator, title: indicator.episodeTitle)
                }
            }
        }
        .animation(theme.motion.smooth, value: indicator)
        .sensoryFeedback(.success, trigger: indicator == .done) { _, done in done }
    }
}

extension EpisodeDownloadRecord {
    var indicator: DownloadIndicator {
        switch state {
        case .queued, .downloading: .inProgress(progress)
        case .done: .done
        case .failed: .failed
        }
    }
}

extension DownloadIndicator {
    var episodeTitle: String {
        switch self {
        case .none: "Download"
        case let .inProgress(progress): "Downloading, \(Int(progress * 100)) percent"
        case .done: "Downloaded"
        case .failed: "Download Failed, Retry"
        }
    }
}

/// The ⋯ button on an episode, with the same actions as its long-press menu.
struct EpisodeMenuButton: View {
    @Environment(\.theme) private var theme
    let item: EpisodeItem

    var body: some View {
        Menu {
            EpisodeMenu(item: item)
        } label: {
            Glyph.more.image
                .foregroundStyle(theme.palette.accent)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("More for \(item.episode.title)")
    }
}

/// Episode actions: play, Up Next, download, save, played state, and go to show.
struct EpisodeMenu: View {
    @Environment(PodcastsStore.self) private var podcasts
    @Environment(AudioPlayer.self) private var player
    @Environment(\.pushPodcastRoute) private var push
    let item: EpisodeItem
    var includeGoToShow = true

    var body: some View {
        let episode = item.episode
        Button(episode.isInProgress ? "Resume" : "Play", glyph: .play) { podcasts.play(item) }
        Button("Play Next", glyph: .playNext) { podcasts.playNext(item) }
        Button("Play Last", glyph: .addToQueue) { podcasts.playLast(item) }
        Divider()
        switch podcasts.downloadStates[item.id]?.state {
        case .done?:
            Button("Remove Download", glyph: .trash, role: .destructive) { podcasts.removeDownload(item.id) }
        case .queued?, .downloading?:
            Button("Cancel Download", glyph: .close) { podcasts.removeDownload(item.id) }
        case .failed?, nil:
            Button("Download", glyph: .download) { podcasts.download(item) }
        }
        Button(episode.isSaved ? "Unsave" : "Save Episode", glyph: episode.isSaved ? .saved : .save) {
            podcasts.setSaved(item.id, !episode.isSaved)
        }
        Button(episode.isPlayed ? "Mark as Unplayed" : "Mark as Played", glyph: .check) {
            podcasts.setPlayed([item.id], !episode.isPlayed)
        }
        if includeGoToShow {
            Divider()
            Button("Go to Show", glyph: .podcasts) { push(.show(ShowRoute(item.show))) }
        }
    }
}

/// An episode tile for Home's podcast shelves: art, show, title and time left.
struct EpisodeCard: View {
    @Environment(\.theme) private var theme
    @Environment(\.pushPodcastRoute) private var push
    let item: EpisodeItem

    var body: some View {
        // A button, not a tap gesture, so the card presses in under the finger like album tiles.
        Button { push(.episode(id: item.id)) } label: {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                ArtworkView(.unsized(item.artworkURL, maxPixelWidth: 840), cornerRadius: theme.radius.small)
                    .overlay(alignment: .topLeading) {
                        if let label {
                            Text(label)
                                .font(theme.typography.caption.weight(.bold))
                                .textCase(.uppercase)
                                // Inverse of the play pill: tan text on a dark capsule, so it reads on light art.
                                .foregroundStyle(theme.palette.accent)
                                .padding(.horizontal, theme.spacing.sm)
                                .padding(.vertical, theme.spacing.xxs)
                                .background(theme.palette.background, in: .capsule)
                                .padding(theme.spacing.sm)
                        }
                    }
                // Show and title read as one unit, so they sit closer than the rest of the card.
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(item.show.title)
                        .font(theme.typography.caption.weight(.semibold))
                        .foregroundStyle(theme.palette.textSecondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    Text(item.episode.title)
                        .font(theme.typography.itemTitle)
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
                // Time left as plain text, matching album tiles; tapping the card opens the episode.
                Text(EpisodeFormat.status(item.episode))
                    .font(theme.typography.itemSubtitle)
                    .foregroundStyle(theme.palette.textSecondary)
                    .monospacedDigit()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .contextMenu { EpisodeMenu(item: item) }
    }

    private var label: String? {
        if item.episode.isInProgress { return "Resume" }
        if Calendar.current.isDateInToday(item.episode.publishedAt ?? .distantPast) { return "New" }
        return nil
    }
}

/// Show art with title and a new-episode count, for grids and shelves.
struct ShowTile: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String
    let artworkURL: URL?
    var newCount = 0

    var body: some View {
        AlbumTile(title: title, subtitle: subtitle, artwork: .unsized(artworkURL, maxPixelWidth: 480))
            .overlay(alignment: .topTrailing) {
                if newCount > 0 {
                    Text("\(newCount)")
                        .font(theme.typography.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.palette.onAccent)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(theme.palette.accent, in: .capsule)
                        .padding(theme.spacing.xs)
                        .accessibilityLabel("\(newCount) new episodes")
                }
            }
    }
}
