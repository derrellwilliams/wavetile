import SwiftUI
import UIKit

/// Plexamp-style ambient background: a slowly drifting mesh gradient tinted by the artwork.
public struct ArtworkBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private let colors: [Color]
    @State private var drift = false

    /// - Parameter colors: dominant artwork colors, e.g. from `ArtworkColors.extract(from:)`. 2–4 work best.
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

/// Extracts a small palette from an image by downsampling. Call off the main actor.
public enum ArtworkColors {
    public nonisolated static func extract(from image: UIImage, count: Int = 4) -> [Color] {
        guard let cgImage = image.cgImage else { return [] }
        let side = 4
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let samples = stride(from: 0, to: pixels.count, by: 4).map { i in
            (Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
        }
        // Prefer saturated samples so the background isn't muddy.
        return samples
            .sorted { saturation($0) > saturation($1) }
            .prefix(count)
            .map { Color(red: $0.0, green: $0.1, blue: $0.2) }
    }

    private nonisolated static func saturation(_ rgb: (Double, Double, Double)) -> Double {
        let maxV = max(rgb.0, rgb.1, rgb.2), minV = min(rgb.0, rgb.1, rgb.2)
        return maxV == 0 ? 0 : (maxV - minV) / maxV
    }
}

#Preview {
    ArtworkBackground(colors: PlaceholderPalette.colors(seed: 2) + PlaceholderPalette.colors(seed: 6))
}
