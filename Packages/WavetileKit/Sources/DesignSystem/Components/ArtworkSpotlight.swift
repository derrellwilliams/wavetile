import Nuke
import NukeUI
import SwiftUI

/// A smaller alternative to `ArtworkHero`: the art as a centered square over a very abstract
/// blur of the same art, darkened by a scrim. The color fills the whole area behind the art and
/// only fades into the page below it. Used on episode pages, where full-width show art read too big.
public struct ArtworkSpotlight: View {
    @Environment(\.theme) private var theme
    private let artwork: ArtworkSource
    private let size: CGFloat

    /// Space below the art inside this view.
    private let gap: CGFloat = 40
    /// How far the color runs past this view, behind the title, while it fades out.
    private let overhang: CGFloat = 120
    /// Length of the fade; it starts just above the art's bottom edge.
    private let fade: CGFloat = 200

    public init(artwork: ArtworkSource, size: CGFloat = 232) {
        self.artwork = artwork
        self.size = size
    }

    public var body: some View {
        ArtworkView(artwork, cornerRadius: theme.radius.small)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
            // Clears the status bar and the navigation bar's buttons (the page runs under them),
            // with room to breathe below the grouped toolbar actions.
            .padding(.top, 118)
            .padding(.bottom, gap)
            .frame(maxWidth: .infinity)
            // Extends below the view so the fade can be long without pushing the title down.
            .background(alignment: .top) { backdrop.padding(.bottom, -overhang) }
            .accessibilityElement(children: .contain)
    }

    private var backdrop: some View {
        GeometryReader { proxy in
            // Oversized so the blur's soft edges fall outside the clip.
            let side = max(proxy.size.width, proxy.size.height) * 1.5
            blurredArt
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .clipped()
        // Dark screen in both themes, so the art stands off it and the bar buttons stay legible.
        .overlay(Color.black.opacity(0.2))
        .overlay(alignment: .bottom) {
            // Eased (smoothstep) rather than linear, so there's no visible line where it starts.
            LinearGradient(
                stops: stride(from: 0.0, through: 1.0, by: 0.125).map { t in
                    .init(color: theme.palette.background.opacity(t * t * (3 - 2 * t)), location: t)
                },
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fade)
        }
        .accessibilityHidden(true)
    }

    /// Heavy enough that the art reads only as its colors. The blur is baked into a 64px copy
    /// once (and cached), then scaled up, instead of blurring the full-size art live while the page scrolls.
    @ViewBuilder private var blurredArt: some View {
        switch artwork {
        case let .url(url), let .unsized(url, _):
            let size = CGSize(width: 64, height: 64)
            let request = url.map {
                ImageRequest(url: $0, processors: [.resize(size: size, unit: .pixels, contentMode: .aspectFill, crop: true), .gaussianBlur(radius: 8)])
            }
            LazyImage(request: request, transaction: Transaction(animation: theme.motion.snappy)) { state in
                if let image = state.image { image.resizable().scaledToFill() }
            }
        case .placeholder:
            ArtworkView(artwork, cornerRadius: 0).blur(radius: 80)
        }
    }
}
