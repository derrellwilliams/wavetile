import DesignSystem
import SwiftUI
import UIKit

/// App entry view: applies the theme and switches between sign-in and the main UI.
public struct RootView: View {
    @ObserveInjection var inject
    let app: AppModel
    /// Covers the first moments after launch with the turning cube over the drifting waves,
    /// picking up from the launch image.
    @State private var showsSplash = true

    public init(app: AppModel) {
        self.app = app
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
        .overlay {
            if showsSplash {
                // Starts as the static launch screen (the cube over "Wavetile"), so launch hands off without a jump.
                SplashScreen()
                    .transition(.opacity)
            }
        }
        .animation(app.theme.motion.smooth, value: phaseKey)
        .environment(\.theme, app.theme)
        .tint(app.theme.palette.accent)
        .preferredColorScheme(app.theme.colorScheme)
        .background(app.theme.palette.background.ignoresSafeArea())
        .onAppear { app.restore() }
        .task {
            // One quarter turn and a beat to read the name, then reveal the app.
            try? await Task.sleep(for: .seconds(WavetileMark.move + WavetileMark.hold + 0.15))
            withAnimation(app.theme.motion.smooth) { showsSplash = false }
        }
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
