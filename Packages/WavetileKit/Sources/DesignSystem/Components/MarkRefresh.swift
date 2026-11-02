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
    /// The bottom of the compact navigation bar, in the window. A large title travels down with
    /// the content, so the pull opens its gap here, above the title, not above the content.
    @State private var barBottom: CGFloat?
    /// The indicator layer's top in the window (the screen's top: it ignores the safe area).
    /// `restingInset` and `barBottom` are measured from the window's top too.
    @State private var overlayTop: CGFloat = 0

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
            .overlay(alignment: .top) {
                indicator
                    .frame(maxHeight: .infinity, alignment: .top)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { overlayTop = $0 }
                    .ignoresSafeArea(edges: .top)
            }
            .background {
                CompactBarProbe(isMeasuring: pull == 0 && refreshStart == nil) { bottom in
                    // A late measurement once a pull has begun would catch the bar mid-stretch.
                    guard pull == 0, refreshStart == nil else { return }
                    // Keeps the last measurement if the bar can't be found for a moment.
                    if let bottom { barBottom = bottom }
                }
            }
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
        // Centered in the gap the pull opens under the bar (above the large title, if any).
        .offset(y: (barBottom ?? restingInset ?? 0) - overlayTop + max(0, pull / 2 - Self.size / 2))
        .opacity(refreshStart != nil ? 1 : min(1, Double(pull / 60)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Reports the bottom of the compact navigation bar this screen is in (in the window), or nil
/// outside a navigation stack. Only while `isMeasuring` (at rest).
private struct CompactBarProbe: UIViewRepresentable {
    let isMeasuring: Bool
    let report: (CGFloat?) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard isMeasuring else { return }
        let report = report
        // After layout, so the bar reflects this screen, and again shortly after: a bar can
        // finish laying out a moment after the screen first appears.
        for delay in [0, 0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view] in
                guard let view else { return }
                report(Self.compactBarBottom(near: view))
            }
        }
    }

    /// The bar's frame includes its large title, so its compact part is measured from its
    /// pieces: the compact row is the shallowest of them (the background reaches up under the
    /// status bar, so it's skipped; the large title sits below the row).
    private static func compactBarBottom(near view: UIView) -> CGFloat? {
        var responder: UIResponder? = view
        while let next = responder, !(next is UIViewController) { responder = next.next }
        guard let bar = (responder as? UIViewController)?.navigationController?.navigationBar,
              !bar.isHidden, let window = bar.window
        else { return nil }
        let rowBottom = bar.subviews
            .filter { !$0.isHidden && $0.frame.minY >= 0 && $0.frame.height > 0 }
            .map(\.frame.maxY)
            .min() ?? bar.bounds.height
        return bar.convert(CGPoint(x: 0, y: rowBottom), to: window).y
    }
}

private struct PullGeometry: Equatable {
    var offset: CGFloat
    var inset: CGFloat

    var isAtRest: Bool { abs(offset + inset) < 0.5 }
}
