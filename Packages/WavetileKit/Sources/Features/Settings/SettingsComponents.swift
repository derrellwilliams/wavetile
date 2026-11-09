import DesignSystem
import JellyfinKit
import Nuke
import NukeUI
import SwiftUI

/// A native grouped `Form` in the theme's colors, shared by the Settings drawer and Podcast
/// Settings. Rows are system controls (`LabeledContent`, `Toggle`, menu `Picker`, `Button`)
/// with Phosphor icons; the form handles separators, highlights, headers and large text stacking.
struct SettingsForm<Content: View>: View {
    @Environment(\.theme) private var theme
    var selection: Binding<Set<String>>?
    @ViewBuilder let content: Content

    init(selection: Binding<Set<String>>? = nil, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.content = content()
    }

    var body: some View {
        if let selection {
            styled(List(selection: selection) { Group { content }.listRowBackground(theme.palette.surface) }.listStyle(.insetGrouped))
        } else {
            styled(Form { Group { content }.listRowBackground(theme.palette.surface) })
        }
    }

    private func styled(_ form: some View) -> some View {
        form
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

/// The account's profile picture as a circle, or the Phosphor `user-circle` glyph in the accent color
/// when the account has none (or the picture fails to load).
struct AvatarPicture: View {
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var library: LibraryStore?
    var size: CGFloat = 32

    var body: some View {
        if let url = library?.avatarURL {
            // The server sends the original; shrink it to the circle instead of decoding it whole.
            let request = ImageRequest(
                url: url,
                processors: [.resize(size: CGSize(width: size, height: size), unit: .points, contentMode: .aspectFill, crop: true)]
            )
            LazyImage(request: request) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else if state.error != nil {
                    glyph
                } else {
                    Color.clear
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            glyph
        }
    }

    private var glyph: some View {
        Glyph.user.image
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(theme.palette.accent)
    }
}

/// Profile avatar in the drawer's header.
struct Avatar: View {
    var size: CGFloat = 72

    var body: some View {
        AvatarPicture(size: size)
            .accessibilityHidden(true)
    }
}

/// Available before sign-in and from Settings without sending account details to the website.
struct PrivacyPolicyLink: View {
    private static let url = URL(string: "https://wavetile.com/privacy")!

    var body: some View {
        Link(destination: Self.url) {
            Label("Privacy Policy", glyph: .lock)
        }
        .accessibilityHint("Opens the Wavetile privacy policy in your browser")
    }
}
