import NukeUI
import SwiftUI

/// Where artwork comes from. `.placeholder` gives previews deterministic, network-free art.
public enum ArtworkSource: Hashable, Sendable {
    case url(URL?)
    case placeholder(seed: Int)

    /// Builds a sized request URL for the rendered point size × screen scale.
    public typealias URLProvider = @Sendable (_ pixelWidth: Int) -> URL?
}

/// Square album artwork with themed corner radius, placeholder, and fade-in.
public struct ArtworkView: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale
    private let source: ArtworkSource
    private let cornerRadius: CGFloat?

    public init(_ source: ArtworkSource, cornerRadius: CGFloat? = nil) {
        self.source = source
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? theme.radius.artwork, style: .continuous)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                switch source {
                case let .url(url):
                    LazyImage(url: url, transaction: Transaction(animation: theme.motion.snappy)) { state in
                        if let image = state.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder(seed: url?.hashValue ?? 0)
                        }
                    }
                case let .placeholder(seed):
                    placeholder(seed: seed)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    private func placeholder(seed: Int) -> some View {
        let tones = PlaceholderPalette.colors(seed: seed)
        return LinearGradient(colors: tones, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Glyph.song.image
                    .foregroundStyle(.white.opacity(0.5))
            }
    }
}

/// Deterministic pleasant gradients for placeholders and previews.
public enum PlaceholderPalette {
    private static let hues: [Double] = [0.02, 0.08, 0.13, 0.33, 0.47, 0.55, 0.62, 0.72, 0.83, 0.92]

    public static func colors(seed: Int) -> [Color] {
        let hue = hues[abs(seed) % hues.count]
        return [
            Color(hue: hue, saturation: 0.55, brightness: 0.85),
            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.45),
        ]
    }
}

#Preview {
    HStack {
        ArtworkView(.placeholder(seed: 1))
        ArtworkView(.placeholder(seed: 4))
        ArtworkView(.url(nil))
    }
    .padding()
}
