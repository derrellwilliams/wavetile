import DesignSystem
import SwiftUI
import UIKit

/// App entry view: applies the theme and switches between sign-in and the main UI.
public struct RootView: View {
    @ObserveInjection var inject
    let app: AppModel
    /// Covers the first moments after launch with the turning mark, picking up from the launch image.
    @State private var showsSplash = true

    public init(app: AppModel) {
        self.app = app
        BrandFont.register()
        ImageCaching.configure()
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
        .overlay {
            if showsSplash {
                SplashView()
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
            // One quarter turn, then reveal the app.
            try? await Task.sleep(for: .seconds(WavetileMark.move + 0.15))
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

/// Matches the static launch screen (mark centered on the canvas), so launch hands off without a jump.
private struct SplashView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        theme.palette.background
            .ignoresSafeArea()
            .overlay { WavetileMark(isAnimating: true, size: 96) }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

#Preview("Signed in") {
    RootView(app: .preview())
}

#Preview("Signed out") {
    RootView(app: .preview(signedIn: false))
}
