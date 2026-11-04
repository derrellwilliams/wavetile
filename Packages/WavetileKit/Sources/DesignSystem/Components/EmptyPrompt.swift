import SwiftUI

/// An empty screen's invitation: a title that names what to do, one line on why, and the button
/// that does it (or no button, when the line says it all, as on Favorites). Flush left on the
/// screen margin right under the page title, like the shelves that replace it; no glyph.
/// Podcasts, Playlists, Collections, Favorites and the empty playlist and collection pages use it.
public struct EmptyPrompt: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let message: String
    private let button: String?
    private let action: () -> Void

    public init(_ title: String, message: String, button: String? = nil, action: @escaping () -> Void = {}) {
        self.title = title
        self.message = message
        self.button = button
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(title)
                .font(theme.typography.title)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(theme.typography.body)
                .foregroundStyle(theme.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                PrimaryButton(LocalizedStringKey(button), action: action)
                    .padding(.top, theme.spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.screenInset)
    }
}

#Preview {
    EmptyPrompt("Find Your Shows", message: "Follow a show to see its episodes here.", button: "Find Shows") {}
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.dark.palette.background)
}
