import DesignSystem
import SwiftUI

/// A browse row: glyph and title (Music sections, Podcasts shortcuts).
struct LinkRow: View {
    /// The glyph's column, so titles line up whatever the glyph's own width.
    static let glyphWidth: CGFloat = 28

    @Environment(\.theme) private var theme
    let title: String
    let glyph: Glyph

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            glyph.image
                .foregroundStyle(theme.palette.accent)
                .frame(width: Self.glyphWidth)
            Text(title)
                .font(theme.typography.body)
                .foregroundStyle(theme.palette.textPrimary)
            Spacer()
        }
        .padding(.vertical, theme.spacing.md + 2)
        .contentShape(.rect)
    }
}

/// The hairline between `LinkRow`s, starting under the title.
struct LinkRowDivider: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Divider().overlay(theme.palette.separator).padding(.leading, LinkRow.glyphWidth + theme.spacing.md)
    }
}
