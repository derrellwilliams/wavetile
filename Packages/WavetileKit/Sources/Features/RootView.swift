import DesignSystem
import SwiftUI
import UIKit

/// App entry view: applies the theme and switches between sign-in and the main UI.
public struct RootView: View {
    @ObserveInjection var inject
    let app: AppModel

    public init(app: AppModel) {
        self.app = app
        BrandFont.register()
        BrandFont.applyNavigationBarAppearance(textColor: UIColor(app.theme.palette.textPrimary))
    }

    public var body: some View {
        Group {
            switch app.phase {
            case .launching:
                Color.clear
            case .signedOut:
                SignInFlow(app: app)
                    .transition(.opacity)
            case let .signedIn(signedIn):
                MainTabView(app: app, signedIn: signedIn)
                    .id(signedIn.session)
                    .transition(.opacity)
            }
        }
        .animation(app.theme.motion.smooth, value: phaseKey)
        .environment(\.theme, app.theme)
        .tint(app.theme.palette.accent)
        .preferredColorScheme(app.theme.colorScheme)
        .background(app.theme.palette.background.ignoresSafeArea())
        .onAppear { app.restore() }
        .enableInjection()
    }

    private var phaseKey: Int {
        switch app.phase {
        case .launching: 0
        case .signedOut: 1
        case .signedIn: 2
        }
    }
}

#Preview("Signed in") {
    RootView(app: .preview())
}

#Preview("Signed out") {
    RootView(app: .preview(signedIn: false))
}
