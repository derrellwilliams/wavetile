import SwiftUI
import UIKit

public extension View {
    /// Pull to refresh with the Wavetile mark instead of the system spinner.
    ///
    /// Keeps the system's pull mechanics (threshold, haptic, holding content down while
    /// refreshing) and only replaces what's drawn: the mark fades in and its edges slide around
    /// the frame as you pull, then it keeps turning until `action` finishes.
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

    private static let size: CGFloat = 28
    /// Pull distance for one quarter turn while scrubbing.
    private static let pullPerTurn: CGFloat = 90

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
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, newValue in
                pull = newValue
            }
            .refreshable {
                startTurn = scrubTurn
                refreshStart = .now
                await action()
                refreshStart = nil
            }
            .overlay(alignment: .top) { indicator }
    }

    private var scrubTurn: Double {
        reduceMotion ? 0 : Double(pull / Self.pullPerTurn)
    }

    private var indicator: some View {
        TimelineView(.animation(paused: refreshStart == nil || reduceMotion)) { context in
            let turn = refreshStart.map { startTurn + WavetileMark.turn(at: context.date.timeIntervalSince($0)) } ?? scrubTurn
            Canvas { canvas, size in
                WavetileMark.draw(in: &canvas, size: size, turn: turn, color: theme.palette.accent)
            }
        }
        .frame(width: Self.size, height: Self.size)
        // Centered in the gap the pull opens above the content.
        .offset(y: max(0, pull / 2 - Self.size / 2))
        .opacity(refreshStart != nil ? 1 : min(1, Double(pull / 60)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
