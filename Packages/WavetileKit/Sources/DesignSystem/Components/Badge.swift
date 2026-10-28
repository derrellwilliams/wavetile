import SwiftUI

/// A small accent capsule over artwork, for counts ("3").
public struct Badge: View {
    @Environment(\.theme) private var theme
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(theme.typography.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(theme.palette.background)
            .padding(.horizontal, theme.spacing.sm)
            .frame(minWidth: 22, minHeight: 22)
            .background(theme.palette.accent, in: .capsule)
    }
}
