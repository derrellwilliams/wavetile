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
    /// False from the moment the splash starts to fade: touches and VoiceOver go to the app, not
    /// to the splash still fading out over it.
    @State private var splashCovers = true

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
                    .allowsHitTesting(splashCovers)
                    .accessibilityHidden(!splashCovers)
                    .transition(.opacity)
            }
        }
        .animation(app.theme.motion.smooth, value: phaseKey)
        .environment(\.theme, app.theme)
        // Inter at body size for anything without a font of its own (form rows and headers,
        // toggles, pickers, text fields), so nothing falls back to the system face.
        .font(app.theme.typography.body)
        .lineSpacing(app.theme.typography.textLeading)
        // The main tan for anything without a color of its own (form rows, values), never white;
        // dimmed when disabled, as the system style would be.
        .foregroundStyle(EnabledAwareColor(app.theme.palette.textPrimary))
        .tint(app.theme.palette.accent)
        .preferredColorScheme(app.theme.colorScheme)
        .background(app.theme.palette.background.ignoresSafeArea())
        .onAppear { app.restore() }
        .task {
            // Two quarter turns and a beat to read the name, then reveal the app.
            try? await Task.sleep(for: .seconds(2 * (WavetileMark.move + WavetileMark.hold) + 0.15))
            // Hand the screen over first; the removed splash keeps the state it fades out with.
            splashCovers = false
            await Task.yield()
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
