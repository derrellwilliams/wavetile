import SwiftUI

/// Plexamp-style ambient background: a slowly drifting mesh gradient tinted by the artwork.
public struct ArtworkBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private let colors: [Color]
    @State private var drift = false

    /// - Parameter colors: artwork colors, e.g. an `ArtworkPalette`'s background and accent. 2–4 work best.
    public init(colors: [Color]) {
        self.colors = colors.isEmpty ? [.gray] : colors
    }

    public var body: some View {
        let c = (0..<9).map { colors[$0 % colors.count] }
        let d: Float = drift ? 0.12 : -0.08
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + d, 0.5 - d], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8]]
        )
        .overlay(colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.15))
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(theme.motion.ambient) { drift = true }
        }
        .animation(theme.motion.smooth, value: colors)
    }
}

#Preview {
    ArtworkBackground(colors: PlaceholderPalette.colors(seed: 2) + PlaceholderPalette.colors(seed: 6))
}
