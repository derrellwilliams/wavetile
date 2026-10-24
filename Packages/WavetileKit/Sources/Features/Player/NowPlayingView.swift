import AVKit
import DesignSystem
import Playback
import SwiftUI

/// Full player. Presented as a sheet so swipe-down dismisses it, zooming out of the mini player.
struct NowPlayingView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryStore.self) private var store
    @State private var showQueue = false

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
        .enableInjection()
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
                    Text(player.current?.artist ?? "")
                        .font(theme.typography.nowPlayingSubtitle)
                        .foregroundStyle(theme.palette.textPrimary)
                    if let error = player.errorMessage {
                        Label(error, glyph: .warning)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let trackID = player.current?.trackID {
                    FavoriteButton(itemID: trackID, size: 28)
                }
            }
            .contentTransition(.opacity)
            .animation(theme.motion.smooth, value: player.current?.queueID)

            Scrubber()

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
        ArtworkView(store.artwork(itemID: player.current?.albumID, tag: player.current?.albumImageTag, maxPixelWidth: 1200))
            .shadow(color: .black.opacity(player.isPlaying ? 0.5 : 0.2), radius: player.isPlaying ? 30 : 12, y: 12)
            // Apple Music–style "breathing": artwork recedes when paused.
            .scaleEffect(player.isPlaying || reduceMotion ? 1 : 0.86)
            // State change, not a flick: critically damped, no overshoot.
            .animation(theme.motion.smooth, value: player.isPlaying)
            .id(player.current?.albumID)
            .transition(.opacity)
    }

    private var transport: some View {
        HStack {
            Spacer()
            GlyphButton("Previous", glyph: .previous, size: 34) { player.previous() }
            Spacer()
            GlyphButton(player.isPlaying ? "Pause" : "Play", glyph: player.isPlaying ? .pause : .play, size: 60) {
                player.togglePlayPause()
            }
            .contentTransition(.opacity)
            .overlay(alignment: .bottom) {
                if player.isBuffering { ProgressView().offset(y: 28) }
            }
            Spacer()
            GlyphButton("Next", glyph: .next, size: 34) { player.next() }
            Spacer()
        }
        .buttonStyle(.pressable)
        .foregroundStyle(theme.palette.accent)
        .sensoryFeedback(.impact(weight: .medium), trigger: player.isPlaying)
    }

    private var secondaryControls: some View {
        HStack {
            Button("Shuffle", glyph: .shuffle) { player.toggleShuffle() }
                .foregroundStyle(player.queue.isShuffled ? theme.palette.accent : theme.palette.textSecondary)
                .accessibilityValue(player.queue.isShuffled ? "On" : "Off")
            Spacer()
            AirPlayButton()
                .frame(width: 44, height: 44)
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

/// Seek bar with live drag: the thumb follows the finger and seeks on release.
struct Scrubber: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPlayer.self) private var player
    @State private var dragProgress: Double?

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
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragProgress = min(max(value.location.x / proxy.size.width, 0), 1)
                        }
                        .onEnded { _ in
                            if let dragProgress { player.seek(to: dragProgress * duration) }
                            dragProgress = nil
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

/// System AirPlay picker with a Phosphor glyph: the picker is invisible on top and handles taps.
struct AirPlayButton: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Glyph.airplay.image
                .foregroundStyle(theme.palette.accent)
            RoutePicker()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AirPlay")
    }

    private struct RoutePicker: UIViewRepresentable {
        func makeUIView(context: Context) -> AVRoutePickerView {
            let view = AVRoutePickerView()
            view.tintColor = .clear
            view.activeTintColor = .clear
            view.prioritizesVideoDevices = false
            return view
        }

        func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
    }
}
