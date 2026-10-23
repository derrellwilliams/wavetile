import SwiftUI

/// Named animations. Tune feel here instead of sprinkling `.spring(...)` through views.
public struct Motion: Sendable, Equatable {
    /// Taps, toggles, small state changes.
    public var snappy: Animation
    /// Layout changes, expanding content.
    public var smooth: Animation
    /// Celebratory moments (favorite, track change artwork).
    public var bouncy: Animation
    /// Now Playing background color drift.
    public var ambient: Animation
    /// Scale applied to pressed tiles and buttons.
    public var pressedScale: CGFloat

    public static let standard = Motion(
        snappy: .snappy(duration: 0.25),
        smooth: .smooth(duration: 0.4),
        bouncy: .bouncy(duration: 0.5, extraBounce: 0.1),
        ambient: .easeInOut(duration: 8).repeatForever(autoreverses: true),
        pressedScale: 0.96
    )

    public static let playful = Motion(
        snappy: .spring(response: 0.3, dampingFraction: 0.65),
        smooth: .spring(response: 0.5, dampingFraction: 0.8),
        bouncy: .bouncy(duration: 0.6, extraBounce: 0.25),
        ambient: .easeInOut(duration: 6).repeatForever(autoreverses: true),
        pressedScale: 0.92
    )
}

public extension Motion {
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
            .animation(theme.motion.snappy, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { .init() }
}
