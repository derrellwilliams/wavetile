import DesignSystem
import SwiftUI

struct PasswordSignInView: View {
    @ObserveInjection var inject
    @Bindable var model: SignInModel
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
            } footer: {
                if let error = model.errorMessage {
                    Label(error, glyph: .warning).foregroundStyle(.white)
                }
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Text("Sign In")
                        Spacer()
                        if model.isWorking { ProgressView() }
                    }
                }
                .disabled(username.isEmpty || model.isWorking)
            }
        }
        .themedBackground()
        .navigationTitle(model.server?.name ?? "Sign In")
        .onAppear { focus = .username }
        .enableInjection()
    }

    private func submit() {
        Task { await model.signIn(username: username, password: password) }
    }
}
