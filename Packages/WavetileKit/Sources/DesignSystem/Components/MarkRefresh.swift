import SwiftUI
import UIKit

public extension View {
    /// Pull to refresh with the Wavetile mark instead of the system spinner.
    ///
    /// Keeps the system's pull mechanics (threshold, haptic, holding content down while
    /// refreshing) and only replaces what's drawn: the mark fades in and its edges slide around
    /// the frame as you pull, then it turns briskly until `action` finishes.
    func markRefreshable(action: @escaping @Sendable () async -> Void) -> some View {
        modifier(MarkRefreshModifier(action: action))
    }
}

private struct MarkRefreshModifier: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let action: @Sendable () async -> Void

    @State private var pull: CGFloat = 0
    @State private var refreshStart: Date?
    @State private var startTurn: Double = 0
    /// Where the mark stopped when the refresh finished; held while it fades so it doesn't jump
    /// back to the pull-driven pose. Cleared once the content has settled.
    @State private var endTurn: Double?
    /// The top inset at rest. The refresh control adds its own inset while refreshing; measuring
    /// from this keeps the mark from jumping up when it does.
    @State private var restingInset: CGFloat?

    private static let size: CGFloat = 28
    /// Pull distance for one quarter turn while scrubbing (about three turns by the threshold).
    private static let pullPerTurn: CGFloat = 35
    /// Faster than the loading mark's cadence, so a refresh reads as busy.
    private static let move = 0.4, hold = 0.12

    init(action: @escaping @Sendable () async -> Void) {
        self.action = action
        Self.hideSystemSpinner
    }

    /// SwiftUI's `refreshable` is backed by `UIRefreshControl`; clear its tint so only the mark shows.
    private static let hideSystemSpinner: Void = {
        UIRefreshControl.appearance().tintColor = .clear
    }()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: PullGeometry.self) { geometry in
                PullGeometry(offset: geometry.contentOffset.y, inset: geometry.contentInsets.top)
            } action: { _, position in
                let idle = refreshStart == nil && endTurn == nil
                if idle, position.isAtRest || restingInset == nil { restingInset = position.inset }
                pull = max(0, -(position.offset + (restingInset ?? position.inset)))
                if pull == 0 { endTurn = nil }
            }
            .refreshable {
                endTurn = nil
                startTurn = scrubTurn
                let start = Date.now
                refreshStart = start
                await action()
                endTurn = reduceMotion ? 0 : startTurn + turn(since: start, at: .now)
                refreshStart = nil
            }
            .overlay(alignment: .top) { indicator }
    }

    private var scrubTurn: Double {
        reduceMotion ? 0 : Double(pull / Self.pullPerTurn)
    }

    private func turn(since start: Date, at date: Date) -> Double {
        WavetileMark.turn(at: date.timeIntervalSince(start), move: Self.move, hold: Self.hold)
    }

    /// Grows in with the pull, from 60% to full size before the refresh threshold, so there's
    /// no jump when the refresh starts.
    private var pullScale: CGFloat {
        refreshStart != nil ? 1 : 0.6 + 0.4 * min(1, pull / 50)
    }

    private var indicator: some View {
        TimelineView(.animation(paused: refreshStart == nil || reduceMotion)) { context in
            let turn = refreshStart.map { startTurn + turn(since: $0, at: context.date) } ?? endTurn ?? scrubTurn
            Canvas { canvas, size in
                WavetileMark.draw(in: &canvas, size: size, turn: turn, color: theme.palette.accent)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .scaleEffect(pullScale)
        // Centered in the gap the pull opens above the content.
        .offset(y: max(0, pull / 2 - Self.size / 2))
        .opacity(refreshStart != nil ? 1 : min(1, Double(pull / 60)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PullGeometry: Equatable {
    var offset: CGFloat
    var inset: CGFloat

    var isAtRest: Bool { abs(offset + inset) < 0.5 }
}
