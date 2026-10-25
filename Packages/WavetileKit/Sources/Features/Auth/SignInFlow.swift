import DesignSystem
import SwiftUI

/// Server address → Quick Connect (preferred) or username/password.
struct SignInFlow: View {
    @ObserveInjection var inject
    @Environment(\.theme) private var theme
    @State private var model: SignInModel
    @FocusState private var addressFocused: Bool

    init(app: AppModel) {
        _model = State(initialValue: SignInModel(app: app))
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: theme.spacing.sm) {
                        WavetileMark(isAnimating: true, size: 96, color: theme.palette.surface)
                            // Form rows clip to the section's rounded corners; keep the mark clear of them.
                            .padding(.top, theme.spacing.xl)
                        Text("Connect to Jellyfin")
                            .font(theme.typography.largeTitle)
                            .foregroundStyle(theme.palette.accent)
                            .tracking(theme.typography.displayTracking)
                        Text("Enter the address you use to reach your server.")
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 0, leading: theme.spacing.xs, bottom: theme.spacing.sm, trailing: theme.spacing.xs))
                }

                Section {
                    TextField("music.example.com", text: $model.addressText)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($addressFocused)
                        .onSubmit { Task { await model.connect() } }
                } header: {
                    Text("Server")
                } footer: {
                    footer
                }

                // In a footer, not a row: rows clip to the section's large corner radius.
                Section {} footer: {
                    PrimaryButton("Continue", isWorking: model.isWorking) {
                        Task { await model.connect() }
                    }
                    .disabled(model.addressText.isEmpty || model.isWorking)
                    .listRowInsets(.init())
                }
            }
            .themedBackground()
            .navigationDestination(for: SignInModel.Route.self) { route in
                switch route {
                case .quickConnect: QuickConnectView(model: model)
                case .password: PasswordSignInView(model: model)
                }
            }
            .onAppear { addressFocused = true }
        }
        .enableInjection()
    }

    @ViewBuilder private var footer: some View {
        if let error = model.errorMessage {
            Label(error, glyph: .warning)
                .foregroundStyle(theme.palette.textPrimary)
        } else {
            switch model.transportWarning {
            case .insecureRemote:
                Label("HTTP over the internet sends your password and token unencrypted, and iOS will block it. Use HTTPS.", glyph: .lockOpen)
                    .foregroundStyle(theme.palette.textPrimary)
            case .insecureLocal:
                Label("Unencrypted connection. OK on your home network only.", glyph: .lockOpen)
            case nil:
                EmptyView()
            }
        }
    }
}

#Preview {
    SignInFlow(app: .preview(signedIn: false))
}
