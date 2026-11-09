import Nuke
import NukeUI
import SwiftUI

/// Where artwork comes from. `.placeholder` gives missing artwork and previews a neutral, network-free fallback.
public enum ArtworkSource: Hashable, Sendable {
    case url(URL?)
    /// Art from a third party that serves one big image (podcast feeds often use 3000px).
    /// It's downsampled to `maxPixelWidth` on decode so lists don't hold full-size bitmaps.
    case unsized(URL?, maxPixelWidth: Int)
    case placeholder(seed: Int)
    /// Generated playlist and collection covers (`CoverArt`), drawn on device from a seed.
    case generated(seed: String)

    /// Builds a sized request URL for the rendered point size × screen scale.
    public typealias URLProvider = @Sendable (_ pixelWidth: Int) -> URL?
}

/// Square album artwork with themed corner radius, a quiet loading surface, and fade-in.
public struct ArtworkView: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale
    private let source: ArtworkSource
    private let cornerRadius: CGFloat?
    private let onFailure: (@MainActor @Sendable () -> Void)?

    /// `onFailure` runs when a `.url` or `.unsized` image fails to load (not when it's cancelled),
    /// so a caller with a second URL can fall back to it.
    public init(_ source: ArtworkSource, cornerRadius: CGFloat? = nil, onFailure: (@MainActor @Sendable () -> Void)? = nil) {
        self.source = source
        self.cornerRadius = cornerRadius
        self.onFailure = onFailure
    }

    private func report(_ result: Result<ImageResponse, Error>) {
        guard case let .failure(error) = result else { return }
        if let error = error as? ImagePipeline.Error, case .cancelled = error { return }
        if error is CancellationError { return }
        onFailure?()
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
                            loadingSurface(showsFallback: url == nil || state.error != nil)
                        }
                    }
                    .onCompletion { report($0) }
                case let .unsized(url, maxPixelWidth):
                    let size = CGSize(width: maxPixelWidth, height: maxPixelWidth)
                    let request = url.map { ImageRequest(url: $0, processors: [.resize(size: size, unit: .pixels, contentMode: .aspectFill, crop: true)]) }
                    LazyImage(request: request, transaction: Transaction(animation: theme.motion.snappy)) { state in
                        if let image = state.image {
                            image.resizable().scaledToFill()
                        } else {
                            loadingSurface(showsFallback: url == nil || state.error != nil)
                        }
                    }
                    .onCompletion { report($0) }
                case .placeholder:
                    loadingSurface(showsFallback: true)
                case let .generated(seed):
                    GeneratedCover(seed: seed)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    /// Keeps artwork zooms calm while a larger image loads; missing art gets a discreet icon.
    private func loadingSurface(showsFallback: Bool) -> some View {
        theme.palette.surface
            .overlay {
                if showsFallback {
                    Glyph.song.image
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
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
