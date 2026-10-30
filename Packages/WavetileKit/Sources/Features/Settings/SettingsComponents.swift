import DesignSystem
import JellyfinKit
import SwiftUI

/// A native grouped `Form` in the theme's colors, shared by the Settings drawer and Podcast
/// Settings. Rows are system controls (`LabeledContent`, `Toggle`, menu `Picker`, `Button`)
/// with Phosphor icons; the form handles separators, highlights, headers and large text stacking.
struct SettingsForm<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            Group { content }
                .listRowBackground(theme.palette.surface)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .font(theme.typography.body)
        .labelStyle(.tintedIcon)
        .toggleStyle(.switch)
        .tint(theme.palette.toggle)
        .foregroundStyle(theme.palette.textPrimary)
        .themedBackground()
    }
}

/// A read-only settings row: icon and title, with the value trailing (stacked at large sizes).
/// Read as one element, so VoiceOver says "Address, 192.168…" rather than a bare value.
struct SettingsValue: View {
    let title: String
    let glyph: Glyph
    let value: String

    init(_ title: String, glyph: Glyph, value: String) {
        self.title = title
        self.glyph = glyph
        self.value = value
    }

    var body: some View {
        LabeledContent {
            Text(value)
        } label: {
            Label(title, glyph: glyph)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Profile avatar: the Phosphor `user-circle` glyph in the text color.
struct Avatar: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 52

    var body: some View {
        Glyph.profile.image
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(theme.palette.accent)
            .accessibilityHidden(true)
    }
}
