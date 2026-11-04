import AVKit
import DesignSystem
import Playback
import Podcasts
import SwiftUI

/// Full player. Presented as a sheet so swipe-down dismisses it, zooming out of the mini player.
/// Episodes swap the music controls for podcast ones: skip back/forward, speed, sleep timer
/// and chapters.
struct NowPlayingView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryStore.self) private var store
    @Environment(PodcastsStore.self) private var podcasts
    @State private var showQueue = false
    @State private var showChapters = false
    @State private var playPausePresses = 0
    @State private var chapters: [Chapter] = []
    /// The content's natural height; the sheet is sized to it. Starts from the last height
    /// measured, so the sheet opens at its size instead of opening tall and jumping down.
    @State private var contentHeight: CGFloat = Self.lastHeight
    @MainActor private static var lastHeight: CGFloat = 0

    private var isEpisode: Bool { player.current?.isEpisode == true }

    var body: some View {
        // Fixed spacing, with the sheet sized to fit; scrolls only when large text makes it taller
        // than the screen (instead of squeezing and clipping the text).
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Ignores sub-point jitter so the sheet only resizes for a real change.
                    guard abs(height - contentHeight) > 1 else { return }
                    contentHeight = height
                    Self.lastHeight = height
                }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // The artwork starts at the sheet's top edge.
        .ignoresSafeArea(.container, edges: .top)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight)] : [.large])
        .background(theme.palette.background.ignoresSafeArea())
        .sheet(isPresented: $showQueue) {
            QueueView()
                .presentationDetents([.medium, .large])
                .presentationBackground(theme.palette.background)
        }
        .sheet(isPresented: $showChapters) {
            ChaptersSheet(chapters: chapters)
                .presentationDetents([.medium, .large])
                .presentationBackground(theme.palette.background)
        }
        .task(id: player.current?.trackID) { await loadChapters() }
        .enableInjection()
    }

    private func loadChapters() async {
        chapters = []
        guard let track = player.current, track.isEpisode,
              let item = try? podcasts.database.episodeNow(id: track.trackID)
        else { return }
        let loaded = await podcasts.chapters(for: item.episode)
        guard !Task.isCancelled else { return }
        chapters = loaded
    }

    /// The artwork edge to edge, flush with the sheet's top (the sheet's corners round it), with
    /// Close over it; then one column on the screen margins with fixed gaps: the info and
    /// playback controls, then the secondary controls in a capsule.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
                .overlay(alignment: .topLeading) { closeButton }
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                info
                Scrubber(chapterStarts: chapters.map(\.start))
                transport
            }
            .padding(.vertical, theme.spacing.xl)
            .padding(.horizontal, theme.spacing.screenInset)
            secondaryControls
                .padding(.horizontal, theme.spacing.xl)
                .background(theme.palette.tint, in: .capsule)
                .padding(.horizontal, theme.spacing.screenInset)
        }
        .padding(.bottom, theme.spacing.lg)
    }

    /// Two levels, as in other players: the title (22, main tan), then artist and album, or the
    /// show for an episode (18, subtle).
    private var subtitle: String {
        guard let track = player.current else { return "" }
        if track.isEpisode { return track.albumTitle }
        return [track.artist, track.albumTitle].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    private var info: some View {
        HStack(alignment: .bottom, spacing: theme.spacing.md) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(player.current?.title ?? "")
                    .font(theme.typography.title)
                    .foregroundStyle(theme.palette.textPrimary)
                // An error takes the subtitle's line rather than adding one, and episodes always
                // keep a chapter line (blank until chapters load), so neither changes the sheet's height.
                Group {
                    if let error = player.errorMessage {
                        Label(error, glyph: .warning)
                            .transition(.opacity)
                    } else {
                        Text(subtitle)
                    }
                }
                .font(theme.typography.lead)
                .foregroundStyle(theme.palette.textSecondary)
                if isEpisode { CurrentChapterLabel(chapters: chapters) }
            }
            .animation(theme.motion.smooth, value: player.errorMessage)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let track = player.current {
                if track.isEpisode {
                    SaveEpisodeButton(episodeID: track.trackID, size: 28)
                } else {
                    FavoriteButton(itemID: track.trackID, size: 28)
                }
            }
        }
        .contentTransition(.opacity)
        .animation(theme.motion.smooth, value: player.current?.queueID)
    }

    /// Close only, a tinted circle like the bar buttons (opaque, so it reads over any artwork);
    /// what's playing reads in the info block and the queue is in the capsule.
    private var closeButton: some View {
        Button { dismiss() } label: {
            Glyph.dismiss.image
                .foregroundStyle(theme.palette.accent)
                .frame(width: 44, height: 44)
                .background { TintedBarFill(shape: .circle) }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Close")
        .padding(.leading, theme.spacing.screenInset)
        .padding(.top, theme.spacing.lg)
    }

    /// Square and edge to edge. No shadow or paused "breathing": the art is the sheet's top, not a card on it.
    private var artwork: some View {
        let artworkID = player.current?.podcast?.artworkURL?.absoluteString ?? player.current?.albumID
        // Stacked, so the outgoing and incoming art crossfade in place.
        return ZStack {
            ArtworkView(store.artwork(for: player.current, maxPixelWidth: 1200), cornerRadius: 0)
                .id(artworkID)
                .transition(.blurFade)
        }
        .animation(theme.motion.smooth, value: artworkID)
    }

    /// Back and forward on the column edges, lined up with the controls under the hairline.
    private var transport: some View {
        HStack {
            if isEpisode {
                SkipButton(seconds: player.skipBackInterval, forward: false) { player.skip(by: -player.skipBackInterval) }
            } else {
                GlyphButton("Previous", glyph: .previous, size: 34) { player.previous() }
            }
            Spacer()
            // The main control: a tinted circle like the other tinted buttons, its icon at a normal
            // size so the stroke matches every other icon.
            Button {
                playPausePresses += 1
                player.togglePlayPause()
            } label: {
                (player.isPlaying ? Glyph.pause : Glyph.play).image
                    .resizable()
                    .frame(width: 28, height: 28)
                    .id(player.isPlaying)
                    .transition(.iconSwap)
                    .foregroundStyle(theme.palette.accent)
                    .frame(width: 64, height: 64)
                    .background(theme.palette.tint, in: .circle)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .animation(theme.motion.snappy, value: player.isPlaying)
            .overlay(alignment: .bottom) {
                if player.isBuffering { ProgressView().offset(y: 28) }
            }
            Spacer()
            if isEpisode {
                SkipButton(seconds: player.skipForwardInterval, forward: true) { player.skip(by: player.skipForwardInterval) }
            } else {
                GlyphButton("Next", glyph: .next, size: 34) { player.next() }
            }
        }
        .buttonStyle(.pressable)
        .foregroundStyle(theme.palette.accent)
        // The 34pt icons sit centered in 44pt tap areas; pull them out so their edges meet the margins.
        .padding(.horizontal, isEpisode ? 0 : -5)
        // On the tap only: isPlaying also flips for interruptions and AirPods/Lock Screen commands.
        .sensoryFeedback(.impact(weight: .medium), trigger: playPausePresses)
    }

    /// Last in the capsule, as in other players; in the main tan like AirPlay (an action, not a toggle).
    private var queueButton: some View {
        Button("Queue", glyph: .queue) { showQueue = true }
            .foregroundStyle(theme.palette.accent)
            .frame(minWidth: 44, minHeight: 44)
    }

    @ViewBuilder private var secondaryControls: some View {
        if isEpisode { podcastControls } else { musicControls }
    }

    private var podcastControls: some View {
        HStack {
            Menu {
                Picker("Playback Speed", selection: Binding(get: { player.podcastRate }, set: { podcasts.setRate($0) })) {
                    ForEach(AudioPlayer.podcastRates, id: \.self) { rate in
                        Text("\(Double(rate).formatted())×").tag(rate)
                    }
                }
            } label: {
                Text("\(Double(player.podcastRate).formatted())×")
                    .font(theme.typography.mono(.body))
                    .foregroundStyle(theme.palette.accent)
                    .padding(.horizontal, theme.spacing.sm)
                    .frame(minWidth: 44, minHeight: 44)
                    .controlOn(player.podcastRate != 1)
            }
            .accessibilityLabel("Playback Speed")
            .accessibilityValue("\(Double(player.podcastRate).formatted()) times")
            Spacer()
            SleepTimerMenu()
            Spacer()
            AirPlayButton(iconSize: 24)
            // Only for episodes that have chapters; the Spacers spread the rest evenly without it.
            if !chapters.isEmpty {
                Spacer()
                Button("Chapters", glyph: .chapters) { showChapters = true }
                    .frame(minWidth: 44, minHeight: 44)
            }
            Spacer()
            queueButton
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(theme.palette.accent)
        .frame(height: 44)
        .sensoryFeedback(.selection, trigger: player.podcastRate)
    }

    private var musicControls: some View {
        HStack {
            Button("Shuffle", glyph: .shuffle) { player.toggleShuffle() }
                .frame(minWidth: 44, minHeight: 44)
                .controlOn(player.queue.isShuffled)
                .accessibilityValue(player.queue.isShuffled ? "On" : "Off")
            Spacer()
            SleepTimerMenu()
            Spacer()
            AirPlayButton(iconSize: 24)
            Spacer()
            Button("Repeat", glyph: player.queue.repeatMode == .one ? .repeatOne : .repeat) { player.cycleRepeat() }
                .frame(minWidth: 44, minHeight: 44)
                .controlOn(player.queue.repeatMode != .off)
                .accessibilityValue(player.queue.repeatMode.rawValue)
            Spacer()
            queueButton
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(theme.palette.accent)
        .frame(height: 44)
        .sensoryFeedback(.selection, trigger: player.queue.repeatMode)
        .sensoryFeedback(.selection, trigger: player.queue.isShuffled)
    }
}

/// Seek bar with live drag: moves 1:1 with the finger relative to where it was grabbed (touching
/// doesn't jump the position, like Apple Music) and seeks on release.
struct Scrubber: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPlayer.self) private var player
    /// Chapter start times (seconds); each one after the first cuts a small gap in the bar.
    var chapterStarts: [Double] = []
    @State private var dragProgress: Double?
    /// Playback progress when the drag began; the drag offsets from here.
    @State private var dragStart: Double?

    var body: some View {
        let duration = max(player.duration, 1)
        let progress = dragProgress ?? min(player.currentTime / duration, 1)
        VStack(spacing: theme.spacing.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.palette.textPrimary.opacity(0.18))
                    Capsule().fill(dragProgress == nil ? theme.palette.textPrimary : theme.palette.accent)
                        .frame(width: proxy.size.width * progress)
                }
                .frame(height: dragProgress == nil ? 6 : 10)
                .mask { ChapterGaps(starts: chapterStarts, duration: player.duration, width: proxy.size.width) }
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let start = dragStart ?? progress
                            dragStart = start
                            dragProgress = min(max(start + value.translation.width / proxy.size.width, 0), 1)
                        }
                        .onEnded { value in
                            // A touch without movement only highlights; it never seeks.
                            if let dragProgress, abs(value.translation.width) > 0 { player.seek(to: dragProgress * duration) }
                            dragProgress = nil
                            dragStart = nil
                        }
                )
                .animation(theme.motion.snappy, value: dragProgress == nil)
                // A tick each time the drag crosses into another chapter.
                .sensoryFeedback(.selection, trigger: scrubbedChapter) { old, new in old != nil && new != nil }
            }
            .frame(height: 24)

            HStack {
                Text(Duration.seconds(progress * duration), format: .time(pattern: .minuteSecond))
                Spacer()
                Text("-" + Duration.seconds(max(duration - progress * duration, 0)).formatted(.time(pattern: .minuteSecond)))
            }
            .font(theme.typography.mono(.caption))
            .foregroundStyle(theme.palette.textSecondary)
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(Duration.seconds(player.currentTime).formatted(.time(pattern: .minuteSecond)))
        .accessibilityAdjustableAction { direction in
            let step = 15.0
            switch direction {
            case .increment: player.seek(to: player.currentTime + step)
            case .decrement: player.seek(to: player.currentTime - step)
            @unknown default: break
            }
        }
    }

    /// The chapter under the finger while dragging; nil otherwise.
    private var scrubbedChapter: Int? {
        guard let dragProgress, chapterStarts.count > 1 else { return nil }
        let time = dragProgress * player.duration
        return chapterStarts.lastIndex { $0 <= time } ?? 0
    }
}

/// The system AirPlay picker, showing the standard iOS AirPlay audio icon tinted with the accent.
/// Tapping opens the system speaker list (AirPlay, Bluetooth, this iPhone).
struct AirPlayButton: View {
    @Environment(\.theme) private var theme
    var iconSize: CGFloat = 28
    /// Square tap area; nil in a navigation bar, which sizes its own items.
    var tapSize: CGFloat? = 44

    var body: some View {
        RoutePicker(tint: UIColor(theme.palette.accent))
            .frame(width: iconSize, height: iconSize)
            .frame(width: tapSize, height: tapSize)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("AirPlay")
    }

    private struct RoutePicker: UIViewRepresentable {
        let tint: UIColor

        func makeUIView(context: Context) -> AVRoutePickerView {
            let view = AVRoutePickerView()
            view.prioritizesVideoDevices = false
            return view
        }

        func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
            uiView.tintColor = tint
            uiView.activeTintColor = tint
        }
    }
}

/// Skip back/forward with the interval in the glyph, like Podcasts.
struct SkipButton: View {
    @Environment(\.theme) private var theme
    let seconds: Double
    let forward: Bool
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            ZStack {
                (forward ? Glyph.skipForward : Glyph.skipBack).image
                    .resizable()
                    .frame(width: 40, height: 40)
                Text("\(Int(seconds))")
                    .font(BrandFont.font(fixedSize: Theme.Typography.scale.caption, family: BrandFont.monoFamily))
                    .offset(y: 1)
            }
            .frame(width: 60, height: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(forward ? "Skip Forward \(Int(seconds)) Seconds" : "Skip Back \(Int(seconds)) Seconds")
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}

/// Sleep timer: minutes or the end of the episode (or song). The moon fills with the accent when set.
struct SleepTimerMenu: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        Menu {
            Button(player.current?.isEpisode == false ? "End of Song" : "End of Episode") { player.setSleepTimer(.endOfItem) }
            ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) Minutes") { player.setSleepTimer(.at(.now + Double(minutes) * 60)) }
            }
            if player.sleepTimer != nil {
                Divider()
                Button("Turn Off Timer", role: .destructive) { player.setSleepTimer(nil) }
            }
        } label: {
            HStack(spacing: theme.spacing.xxs) {
                Glyph.sleepTimer.image
                if case let .at(date) = player.sleepTimer {
                    Text(timerInterval: Date.now ... max(date, .now), countsDown: true)
                        .font(theme.typography.mono(.caption))
                        .frame(maxWidth: 48)
                }
            }
            .padding(.horizontal, isCountingDown ? theme.spacing.sm : 0)
            .foregroundStyle(theme.palette.accent)
            .frame(minWidth: 44, minHeight: 44)
            .controlOn(player.sleepTimer != nil)
        }
        .accessibilityLabel("Sleep Timer")
        .accessibilityValue(player.sleepTimer == nil ? "Off" : "On")
        .sensoryFeedback(.selection, trigger: player.sleepTimer)
    }

    private var isCountingDown: Bool {
        if case .at = player.sleepTimer { true } else { false }
    }
}

private extension View {
    /// A switched-on control in the secondary capsule: every icon stays in the accent, and "on"
    /// reads from a backing inset 4pt inside the 44pt tap area (a circle for an icon, a pill for text).
    func controlOn(_ isOn: Bool) -> some View {
        modifier(ControlOnBacking(isOn: isOn))
    }
}

private struct ControlOnBacking: ViewModifier {
    @Environment(\.theme) private var theme
    let isOn: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if isOn {
                    Capsule()
                        .fill(theme.palette.controlOn)
                        .padding(theme.spacing.xs)
                        .transition(.opacity)
                }
            }
            .animation(theme.motion.snappy, value: isOn)
    }
}

/// Bookmark toggle for an episode: the podcast twin of `FavoriteButton` (player and episode page).
struct SaveEpisodeButton: View {
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    let episodeID: String
    /// Nil in a navigation bar: a plain bar item, sized and tinted like its neighbours.
    var size: CGFloat?
    @State private var isSaved = false

    var body: some View {
        button
            .sensoryFeedback(.selection, trigger: isSaved)
            .task(id: episodeID) {
                do {
                    for try await item in podcasts.observe(podcasts.database.episode(id: episodeID)) {
                        let saved = item?.episode.isSaved ?? false
                        if saved != isSaved { withAnimation(theme.motion.snappy) { isSaved = saved } }
                    }
                } catch { Log.observationFailed(error) }
            }
    }

    @ViewBuilder private var button: some View {
        let title = isSaved ? "Unsave Episode" : "Save Episode"
        let glyph: Glyph = isSaved ? .saved : .save
        if let size {
            GlyphButton(title, glyph: glyph, size: size, action: toggle)
                .foregroundStyle(theme.palette.accent)
        } else {
            Button(title, glyph: glyph, action: toggle)
        }
    }

    private func toggle() {
        // Same frame as the tap, so the icon swap answers the touch immediately.
        withAnimation(theme.motion.snappy) { isSaved.toggle() }
        podcasts.setSaved(episodeID, isSaved)
    }
}

/// The chapter playing now. Its own view so the clock (twice a second) redraws only this label,
/// not the whole Now Playing screen.
private struct CurrentChapterLabel: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPlayer.self) private var player
    let chapters: [Chapter]

    var body: some View {
        let chapter = chapters.current(at: player.currentTime)
        // A space keeps the line's height before chapters load or the first one starts.
        Text(chapter?.title ?? " ")
            .font(theme.typography.caption)
            .foregroundStyle(theme.palette.textSecondary)
            .contentTransition(.opacity)
            .animation(theme.motion.smooth, value: chapter)
    }
}

/// The playing episode's chapters; tapping one jumps there.
struct ChaptersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioPlayer.self) private var player
    let chapters: [Chapter]

    var body: some View {
        NavigationStack {
            List(chapters) { chapter in
                ChapterRow(chapter: chapter, isCurrent: chapters.current(at: player.currentTime) == chapter) {
                    player.seek(to: chapter.start)
                    if !player.isPlaying { player.resume() }
                    dismiss()
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            // Brand bar titles and the tinted Back (SwiftUI's own bar appearances ignore the proxy).
            .tintedSystemBack()
        }
    }
}

/// One chapter: start time and title, highlighted while it plays. Shared by the player's
/// chapter sheet and the episode page.
struct ChapterRow: View {
    @Environment(\.theme) private var theme
    let chapter: Chapter
    var isCurrent = false
    /// Padding inside the tap area, so one- and two-line rows get the same space above and
    /// below. Lists add their own row insets and leave this at 0.
    var verticalPadding: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.md) {
                Text(Duration.seconds(chapter.start), format: .time(pattern: chapter.start >= 3600 ? .hourMinuteSecond : .minuteSecond))
                    .font(theme.typography.mono(.caption))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(minWidth: 52, alignment: .leading)
                Text(chapter.title)
                    .font(theme.typography.body)
                    .foregroundStyle(isCurrent ? theme.palette.accent : theme.palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, verticalPadding)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Opaque everywhere except a 2pt gap at each chapter start, so the scrubber reads as
/// segments (like Apple Podcasts).
private struct ChapterGaps: View {
    let starts: [Double]
    let duration: Double
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            guard duration > 0 else { return }
            context.blendMode = .clear
            for start in starts where start > 0 && start < duration {
                let x = width * start / duration
                context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.black))
            }
        }
    }
}

extension [Chapter] {
    /// The chapter playing at `time` (half a second early, so a jump lands in the new one).
    func current(at time: Double) -> Chapter? {
        last { $0.start <= time + 0.5 }
    }
}
