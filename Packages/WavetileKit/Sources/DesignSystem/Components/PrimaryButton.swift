import SwiftUI

/// Content buttons in the Apple Music / Apple Podcasts style: a faint wash of the accent with an
/// accent label. Capsules hold the main actions (Play, Shuffle, Retry); pills are the small
/// inline version (an episode row's play button). Glass is left to what floats above content
/// (toolbars, tab bar, mini player).
public struct TintedButtonStyle: ButtonStyle {
    public enum Size: Sendable { case regular, small }

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let size: Size
    /// Off while a button shows its spinner: it's busy, not unavailable, so it stays solid.
    var dimsWhenDisabled = true

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        sized(configuration.label)
            .foregroundStyle(theme.palette.accent)
            .background(pressed ? theme.palette.tintPressed : theme.palette.tint, in: .capsule)
            // A pill is shorter than a finger; its tap area still reaches 44pt.
            .frame(minHeight: 44)
            .contentShape(.rect)
            .scaleEffect(pressed && !reduceMotion ? theme.motion.pressedScale : 1)
            .animation(pressed ? theme.motion.pressIn : theme.motion.snappy, value: pressed)
            .opacity(isEnabled || !dimsWhenDisabled ? 1 : 0.4)
    }

    @ViewBuilder private func sized(_ label: Configuration.Label) -> some View {
        switch size {
        case .regular:
            label
                .font(theme.typography.body.weight(.semibold))
                // md, not lg: three capsules (Play, Shuffle, About) share a row.
                .padding(.horizontal, theme.spacing.md)
                .frame(minHeight: 48)
        case .small:
            label
                .font(theme.typography.caption.weight(.semibold))
                .padding(.horizontal, theme.spacing.md)
                .frame(minHeight: 28)
        }
    }
}

public extension ButtonStyle where Self == TintedButtonStyle {
    /// A tinted capsule (Play, Shuffle, Retry).
    static var tinted: TintedButtonStyle { .init(size: .regular) }
    /// A small tinted pill for inline actions.
    static func tinted(_ size: TintedButtonStyle.Size) -> TintedButtonStyle { .init(size: size) }
}

/// Low-emphasis actions with no background (Read More, Sign Out): accent label, optional
/// leading glyph, dims while pressed.
public struct TextButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.typography.body.weight(.semibold))
            .foregroundStyle(theme.palette.accent)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.5 : isEnabled ? 1 : 0.4)
            .animation(theme.motion.snappy, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == TextButtonStyle {
    /// An accent text button (Read More, Sign Out).
    static var text: TextButtonStyle { .init() }
}

/// A full-width tinted capsule with an optional leading glyph: the main action on a screen.
/// Swaps the label for a spinner while `isWorking`.
public struct PrimaryButton: View {
    @Environment(\.theme) private var theme
    private let title: LocalizedStringKey
    private let glyph: Glyph?
    private let isWorking: Bool
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, glyph: Glyph? = nil, isWorking: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph
        self.isWorking = isWorking
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: theme.spacing.sm) {
                    glyph?.image
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(title)
                        // Shrinks a little rather than truncating in a crowded row or at large text sizes.
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .opacity(isWorking ? 0 : 1)
                if isWorking {
                    ProgressView().tint(theme.palette.accent)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TintedButtonStyle(size: .regular, dimsWhenDisabled: !isWorking))
    }
}
