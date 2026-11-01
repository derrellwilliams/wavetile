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
            .overlay {
                // Over the bottom 45%, eased (smoothstep) rather than linear: a linear fade shows a
                // line where it starts, most on light art.
                LinearGradient(stops: Self.fade.map { .init(color: theme.palette.background.opacity($0.opacity), location: $0.location) },
                               startPoint: .top, endPoint: .bottom)
            }
    }

    private static let fade: [(location: CGFloat, opacity: Double)] = (0...10).map { step in
        let t = Double(step) / 10
        return (0.55 + 0.45 * t, t * t * (3 - 2 * t))
    }
}
