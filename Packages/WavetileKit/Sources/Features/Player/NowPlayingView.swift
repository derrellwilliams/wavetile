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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryStore.self) private var store
    @Environment(PodcastsStore.self) private var podcasts
    @State private var showQueue = false
    @State private var showChapters = false
    @State private var playPausePresses = 0
    @State private var chapters: [Chapter] = []

    private var isEpisode: Bool { player.current?.isEpisode == true }

    var body: some View {
        // Fixed, full-screen layout when it fits; scrolls when large text makes it taller than
        // the screen (instead of squeezing and clipping the text).
        ViewThatFits(in: .vertical) {
            content(scrolling: false)
            ScrollView {
                content(scrolling: true)
            }
            .scrollIndicators(.hidden)
        }
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

    private func content(scrolling: Bool) -> some View {
        VStack(spacing: theme.spacing.xl) {
            header

            if !scrolling { Spacer(minLength: 0) }

            artwork

            if !scrolling { Spacer(minLength: 0) }

            HStack(alignment: .center, spacing: theme.spacing.md) {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(player.current?.title ?? "")
                        .font(theme.typography.nowPlayingTitle)
                        .foregroundStyle(theme.palette.textPrimary)
                    Text((isEpisode ? player.current?.albumTitle : player.current?.artist) ?? "")
                        .font(theme.typography.nowPlayingSubtitle)
                        .foregroundStyle(theme.palette.textPrimary)
                    if let chapter = currentChapter {
                        Text(chapter.title)
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.palette.textSecondary)
                            .contentTransition(.opacity)
                            .animation(theme.motion.smooth, value: chapter)
                    }
                    if let error = player.errorMessage {
                        Label(error, glyph: .warning)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.palette.textSecondary)
                            .transition(.opacity)
                    }
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

            Scrubber(chapterStarts: chapters.map(\.start))

            transport

            secondaryControls
        }
        .padding(.horizontal, theme.spacing.xl)
        .padding(.bottom, theme.spacing.lg)
    }

    private var header: some View {
        HStack {
            Button("Close", glyph: .dismiss) { dismiss() }
            Spacer()
            VStack(spacing: 2) {
                Text("PLAYING FROM")
                    .font(theme.typography.caption.weight(.semibold))
                    .kerning(1)
                    .foregroundStyle(theme.palette.textSecondary)
                Text(player.current?.albumTitle ?? "")
                    .font(theme.typography.itemTitle)
                    .foregroundStyle(theme.palette.textPrimary)
                    // Two lines normally; unlimited at accessibility sizes.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Queue", glyph: .queue) { showQueue = true }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(theme.palette.accent)
        .padding(.top, theme.spacing.lg)
    }

    private var artwork: some View {
        ArtworkView(store.artwork(for: player.current, maxPixelWidth: 1200))
            // Fixed radius: only the shadow's opacity animates (radius changes re-render a big blur every frame).
            .shadow(color: .black.opacity(player.isPlaying ? 0.5 : 0.2), radius: 24, y: 12)
            // Apple Music–style "breathing": artwork recedes when paused.
            .scaleEffect(player.isPlaying || reduceMotion ? 1 : 0.86)
            // State change, not a flick: critically damped, no overshoot.
            .animation(theme.motion.smooth, value: player.isPlaying)
            .id(player.current?.podcast?.artworkURL?.absoluteString ?? player.current?.albumID)
            .transition(.opacity)
    }

    /// The chapter playing now, if the episode has chapters.
    private var currentChapter: Chapter? {
        chapters.current(at: player.currentTime)
    }

    private var transport: some View {
        HStack {
            Spacer()
            if isEpisode {
                SkipButton(seconds: player.skipBackInterval, forward: false) { player.skip(by: -player.skipBackInterval) }
            } else {
                GlyphButton("Previous", glyph: .previous, size: 34) { player.previous() }
            }
            Spacer()
            GlyphButton(player.isPlaying ? "Pause" : "Play", glyph: player.isPlaying ? .pause : .play, size: 60) {
                playPausePresses += 1
                player.togglePlayPause()
            }
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
            Spacer()
        }
        .buttonStyle(.pressable)
        .foregroundStyle(theme.palette.accent)
        // On the tap only: isPlaying also flips for interruptions and AirPods/Lock Screen commands.
        .sensoryFeedback(.impact(weight: .medium), trigger: playPausePresses)
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
                    .font(theme.typography.itemTitle.monospacedDigit())
                    .foregroundStyle(player.podcastRate == 1 ? theme.palette.textSecondary : theme.palette.accent)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Playback Speed")
            .accessibilityValue("\(Double(player.podcastRate).formatted()) times")
            Spacer()
            SleepTimerMenu()
            Spacer()
            AirPlayButton()
            Spacer()
            Button("Chapters", glyph: .chapters) { showChapters = true }
                .foregroundStyle(chapters.isEmpty ? theme.palette.textSecondary.opacity(0.4) : theme.palette.accent)
                .disabled(chapters.isEmpty)
                .frame(minWidth: 44, minHeight: 44)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .frame(height: 44)
        .sensoryFeedback(.selection, trigger: player.podcastRate)
    }

    private var musicControls: some View {
        HStack {
            Button("Shuffle", glyph: .shuffle) { player.toggleShuffle() }
                .foregroundStyle(player.queue.isShuffled ? theme.palette.accent : theme.palette.textSecondary)
                .accessibilityValue(player.queue.isShuffled ? "On" : "Off")
            Spacer()
            AirPlayButton()
            Spacer()
            Button("Repeat", glyph: player.queue.repeatMode == .one ? .repeatOne : .repeat) { player.cycleRepeat() }
                .foregroundStyle(player.queue.repeatMode == .off ? theme.palette.textSecondary : theme.palette.accent)
                .accessibilityValue(player.queue.repeatMode.rawValue)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
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
            }
            .frame(height: 24)

            HStack {
                Text(Duration.seconds(progress * duration), format: .time(pattern: .minuteSecond))
                Spacer()
                Text("-" + Duration.seconds(max(duration - progress * duration, 0)).formatted(.time(pattern: .minuteSecond)))
            }
            .font(theme.typography.caption.monospacedDigit())
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
}

/// The system AirPlay picker, showing the standard iOS AirPlay audio icon tinted with the accent.
/// Tapping opens the system speaker list (AirPlay, Bluetooth, this iPhone).
struct AirPlayButton: View {
    @Environment(\.theme) private var theme
    var iconSize: CGFloat = 28

    var body: some View {
        RoutePicker(tint: UIColor(theme.palette.accent))
            .frame(width: iconSize, height: iconSize)
            .frame(width: 44, height: 44)
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
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
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

/// Sleep timer: minutes or the end of the episode. The moon fills with the accent when set.
struct SleepTimerMenu: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        Menu {
            Button("End of Episode") { player.setSleepTimer(.endOfEpisode) }
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
                        .font(theme.typography.caption.monospacedDigit())
                        .frame(maxWidth: 48)
                }
            }
            .foregroundStyle(player.sleepTimer == nil ? theme.palette.textSecondary : theme.palette.accent)
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Sleep Timer")
        .accessibilityValue(player.sleepTimer == nil ? "Off" : "On")
        .sensoryFeedback(.selection, trigger: player.sleepTimer)
    }
}

/// Bookmark toggle for an episode: the podcast twin of `FavoriteButton` (player and episode page).
struct SaveEpisodeButton: View {
    @Environment(\.theme) private var theme
    @Environment(PodcastsStore.self) private var podcasts
    let episodeID: String
    var size: CGFloat = 24
    @State private var isSaved = false

    var body: some View {
        GlyphButton(isSaved ? "Unsave Episode" : "Save Episode", glyph: isSaved ? .saved : .save, size: size) {
            // Same frame as the tap, so the icon swap answers the touch immediately.
            withAnimation(theme.motion.snappy) { isSaved.toggle() }
            podcasts.setSaved(episodeID, isSaved)
        }
        .foregroundStyle(theme.palette.accent)
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
                    .font(theme.typography.caption.monospacedDigit())
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(minWidth: 52, alignment: .leading)
                Text(chapter.title)
                    .font(isCurrent ? theme.typography.body.weight(.semibold) : theme.typography.body)
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
