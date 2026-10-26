import DesignSystem
import SwiftUI

/// A browse row: glyph, title, chevron (Music sections, Podcasts shortcuts).
struct LinkRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let glyph: Glyph

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            glyph.image
                .foregroundStyle(theme.palette.accent)
                .frame(width: 28)
            Text(title)
                .font(theme.typography.sectionHeader)
                .foregroundStyle(theme.palette.textPrimary)
            Spacer()
            Glyph.chevron.image
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(theme.palette.textSecondary)
        }
        .padding(.vertical, theme.spacing.md + 2)
        .contentShape(.rect)
    }
}
