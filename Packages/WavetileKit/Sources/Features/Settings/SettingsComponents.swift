import DesignSystem
import JellyfinKit
import SwiftUI

/// Grouped card section with a small caps header, shared by Profile and the Settings drawer.
struct SettingsSection<Rows: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            Text(title.uppercased())
                .font(theme.typography.caption.weight(.semibold))
                .kerning(1)
                .foregroundStyle(theme.palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { rows }
                .background(theme.palette.surface, in: .rect(cornerRadius: theme.radius.card, style: .continuous))
        }
    }
}

struct SettingsRow: View {
    @Environment(\.theme) private var theme
    let glyph: Glyph
    let title: String
    let value: String

    init(_ glyph: Glyph, _ title: String, value: String) {
        self.glyph = glyph
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            glyph.image
                .foregroundStyle(theme.palette.textSecondary)
            Text(title)
                .font(theme.typography.body)
                .foregroundStyle(theme.palette.textPrimary)
            Spacer(minLength: theme.spacing.sm)
            Text(value)
                .font(theme.typography.itemSubtitle)
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.md + 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Initial-in-a-circle avatar until we load the Jellyfin profile image.
struct Avatar: View {
    @Environment(\.theme) private var theme
    let name: String
    var size: CGFloat = 52

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            // Scales with the circle so the initial never crowds the edge.
            .font(BrandFont.font(fixedSize: size * 0.48, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(theme.palette.accent, in: .circle)
            .accessibilityHidden(true)
    }
}
