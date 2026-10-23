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
                            .foregroundStyle(.red)
                        Button("Try Again") { model.startQuickConnect() }
                            .buttonStyle(.glass)
                    }
                }

                Button("Sign in with password instead") {
                    model.path = [.password]
                }
                .font(theme.typography.itemSubtitle)
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
                Button("Copy Code", glyph: .copy) {
                    UIPasteboard.general.string = code
                }
                .buttonStyle(.glass)
            }
            .padding(theme.spacing.xl)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: theme.radius.card))
        } else if model.errorMessage == nil {
            ProgressView().controlSize(.large).padding(theme.spacing.xxl)
        }
    }
}
