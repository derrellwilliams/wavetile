import DesignSystem
import JellyfinKit
import PreviewSupport
import SwiftUI

/// Profile and settings, revealed under the main UI by `SideDrawer` (opened from the Home avatar).
struct SettingsDrawer: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Bindable var app: AppModel
    let session: ServerSession
    @Binding var isOpen: Bool
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xxl) {
                profileHeader

                SettingsSection(title: "Account") {
                    SettingsRow(.server, "Server", value: session.serverName)
                    SettingsRow(.address, "Address", value: session.serverURL.host() ?? session.serverURL.absoluteString)
                    SettingsRow(
                        session.serverURL.scheme == "https" ? .lock : .lockOpen,
                        "Connection",
                        value: session.serverURL.scheme == "https" ? "Encrypted" : "Unencrypted"
                    )
                }

                SettingsSection(title: "Appearance") {
                    Menu {
                        Picker("Theme", selection: $app.theme) {
                            ForEach(Theme.all) { theme in
                                Text(theme.name).tag(theme)
                            }
                        }
                    } label: {
                        SettingsRow(.appearance, "Theme", value: app.theme.name)
                    }
                }

                Button {
                    confirmSignOut = true
                } label: {
                    Label("Sign Out", glyph: .signOut)
                        .font(theme.typography.body.weight(.semibold))
                        .foregroundStyle(theme.palette.accent)
                }
                .confirmationDialog("Sign out of \(session.serverName)?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                    Button("Sign Out", role: .destructive) {
                        Task { await app.signOut() }
                    }
                }
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.vertical, theme.spacing.lg)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(theme.palette.textPrimary)
        .background(theme.palette.background.ignoresSafeArea())
        .enableInjection()
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            Avatar(name: session.userName)
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(session.userName)
                    .font(theme.typography.title)
                Text(session.serverName)
                    .font(theme.typography.itemSubtitle)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .lineLimit(1)
        }
        .padding(.top, theme.spacing.lg)
    }
}

#Preview {
    @Previewable @State var isOpen = true
    SettingsDrawer(app: .preview(), session: Fixtures.session, isOpen: $isOpen)
}
