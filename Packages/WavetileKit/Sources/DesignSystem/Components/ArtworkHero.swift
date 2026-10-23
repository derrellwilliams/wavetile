import SwiftUI

/// Edge-to-edge square artwork at the top of a detail page. Its bottom edge fades into the
/// page background so the art doesn't end on a hard line.
public struct ArtworkHero: View {
    @Environment(\.theme) private var theme
    private let artwork: ArtworkSource

    public init(artwork: ArtworkSource) {
        self.artwork = artwork
    }

    public var body: some View {
        ArtworkView(artwork, cornerRadius: 0)
            .overlay(alignment: .bottom) {
                // Fade over the bottom quarter only; the rest of the art stays untouched.
                VStack(spacing: 0) {
                    Color.clear
                    Color.clear
                    Color.clear
                    LinearGradient(
                        colors: [theme.palette.background.opacity(0), theme.palette.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
    }
}
