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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let glyph: Glyph
    let title: String
    let value: String

    init(_ glyph: Glyph, _ title: String, value: String) {
        self.glyph = glyph
        self.title = title
        self.value = value
    }

    var body: some View {
        // Side by side when label and value both fit on one line; otherwise stacked (like iOS
        // Settings) so neither has to break mid-word or truncate, at any text size.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.md) {
                titleLabel
                Spacer(minLength: theme.spacing.sm)
                valueText.fixedSize()
            }
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                titleLabel
                valueText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? theme.spacing.md : theme.spacing.lg)
        .padding(.vertical, theme.spacing.md + 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var titleLabel: some View {
        HStack(spacing: theme.spacing.md) {
            glyph.image
                .foregroundStyle(theme.palette.textSecondary)
            Text(title)
                .font(theme.typography.body)
                .foregroundStyle(theme.palette.textPrimary)
                .fixedSize()
        }
    }

    @ViewBuilder private var valueText: some View {
        if !value.isEmpty {
            Text(value)
                .font(theme.typography.itemSubtitle)
                .foregroundStyle(theme.palette.textSecondary)
        }
    }
}

/// Profile avatar: black circle with a person glyph.
struct Avatar: View {
    var size: CGFloat = 52

    var body: some View {
        Glyph.user.image
            .resizable()
            .scaledToFit()
            // Scales with the circle so the glyph never crowds the edge.
            .frame(width: size * 0.5, height: size * 0.5)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.black, in: .circle)
            .accessibilityHidden(true)
    }
}
