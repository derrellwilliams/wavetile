import DesignSystem
import SwiftUI

struct QuickConnectView: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @Bindable var model: SignInModel

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.xl) {
                VStack(spacing: theme.spacing.sm) {
                    Text("Quick Connect")
                        .font(theme.typography.title)
                    Text("On a device that's already signed in, open **Settings → Quick Connect** and enter this code.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.palette.textSecondary)
                }

                codeView

                if let error = model.errorMessage {
                    VStack(spacing: theme.spacing.md) {
                        Label(error, glyph: .warning)
                            .foregroundStyle(theme.palette.textPrimary)
                        PrimaryButton("Try Again") { model.startQuickConnect() }
                    }
                }

                Button("Sign in with password instead") {
                    model.path = [.password]
                }
                .buttonStyle(.text)
            }
            .padding(theme.spacing.screenInset)
            .frame(maxWidth: .infinity)
        }
        .themedBackground()
        .navigationTitle(model.server?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.startQuickConnect() }
        .onDisappear { model.stopQuickConnect() }
        .enableInjection()
    }

    @ViewBuilder private var codeView: some View {
        if let code = model.quickConnectCode {
            VStack(spacing: theme.spacing.md) {
                Text(code)
                    .font(theme.typography.code)
                    .kerning(6)
                    .contentTransition(.numericText())
                    .textSelection(.enabled)
                    .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
                HStack(spacing: theme.spacing.sm) {
                    ProgressView()
                    Text("Waiting for approval…")
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .font(theme.typography.itemSubtitle)
                PrimaryButton("Copy Code") {
                    UIPasteboard.general.string = code
                }
            }
            .padding(theme.spacing.xl)
            .frame(maxWidth: .infinity)
            .background(theme.palette.surface, in: .rect(cornerRadius: theme.radius.card))
        } else if model.errorMessage == nil {
            LoadingMark(size: 48).padding(theme.spacing.xxl)
        }
    }
}
