import SwiftUI

/// Named animations. Tune feel here instead of sprinkling `.spring(...)` through views.
///
/// Follows Apple's fluid-interface guidance (WWDC18 "Designing Fluid Interfaces"):
/// - UI that just changes state uses critically damped springs (damping 1.0): no overshoot.
/// - Bounce is reserved for motion that follows a gesture with momentum (`momentum(initialVelocity:)`).
public struct Motion: Sendable, Equatable {
    /// Taps, toggles, small state changes. Critically damped.
    public var snappy: Animation
    /// Layout changes, expanding content. Critically damped.
    public var smooth: Animation
    /// Kept for deliberate flourishes only; prefer `snappy`/`smooth` unless motion follows a flick.
    public var bouncy: Animation
    /// Spring for settling after a drag/flick (drawers, sheets). Apple ships damping 0.8, response 0.3.
    public var momentumSpring: Spring
    /// Now Playing background color drift.
    public var ambient: Animation
    /// Scale applied to pressed tiles and buttons.
    public var pressedScale: CGFloat
    /// Press-in: lands almost instantly so the touch feels direct. Release uses `snappy`.
    public var pressIn: Animation = .spring(response: 0.12, dampingFraction: 1)

    public static let standard = Motion(
        snappy: .spring(response: 0.3, dampingFraction: 1),
        smooth: .spring(response: 0.4, dampingFraction: 1),
        bouncy: .bouncy(duration: 0.5, extraBounce: 0.1),
        momentumSpring: Spring(response: 0.3, dampingRatio: 0.8),
        ambient: .easeInOut(duration: 8).repeatForever(autoreverses: true),
        pressedScale: 0.96
    )

    public static let playful = Motion(
        snappy: .spring(response: 0.3, dampingFraction: 0.65),
        smooth: .spring(response: 0.5, dampingFraction: 0.8),
        bouncy: .bouncy(duration: 0.6, extraBounce: 0.25),
        momentumSpring: Spring(response: 0.35, dampingRatio: 0.7),
        ambient: .easeInOut(duration: 6).repeatForever(autoreverses: true),
        pressedScale: 0.92
    )
}

public extension Motion {
    /// Settle after a gesture, continuing at the finger's speed so there's no seam between
    /// dragging and animating. `initialVelocity` is relative: release velocity ÷ distance remaining.
    func momentum(initialVelocity: Double) -> Animation {
        .interpolatingSpring(momentumSpring, initialVelocity: initialVelocity.isFinite ? initialVelocity : 0)
    }

    /// Progressive resistance past a boundary (Apple's rubber-band curve): the further you pull,
    /// the less the content follows, instead of a hard stop.
    static func rubberBand(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    }

    /// Returns nil when Reduce Motion is on, so `withAnimation(theme.motion.resolve(...))` degrades to no animation.
    func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Press feedback used by tiles and rows: scale from the theme, respects Reduce Motion.
public struct PressableButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? theme.motion.pressedScale : 1)
            // Asymmetric: the press lands immediately, the release settles.
            .animation(configuration.isPressed ? theme.motion.pressIn : theme.motion.snappy, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { .init() }
}

// MARK: - Icon swap

public extension AnyTransition {
    /// Swapping one icon for another (play ↔ pause, track number ↔ waveform): the outgoing icon
    /// shrinks and blurs out while the new one grows in, so the two never read as a double exposure.
    /// Reduce Motion keeps only the fade.
    static var iconSwap: AnyTransition {
        .modifier(active: IconSwapModifier(isActive: true), identity: IconSwapModifier(isActive: false))
    }
}

private struct IconSwapModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && !reduceMotion ? 0.6 : 1)
            .blur(radius: isActive && !reduceMotion ? 2 : 0)
            .opacity(isActive ? 0 : 1)
    }
}
