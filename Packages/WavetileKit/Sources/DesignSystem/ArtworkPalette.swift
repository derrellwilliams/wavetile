import Nuke
import SwiftUI
import UIKit

/// Colors derived from album art, Apple Music style: the page background continues the
/// artwork's bottom edge so the art bleeds into the page, and controls use the art's most
/// vivid color. Contrast is enforced so white text and button glyphs stay legible.
nonisolated public struct ArtworkPalette: Sendable, Equatable {
    /// Page background; matches the artwork's bottom edge (darkened if needed for white text).
    public var background: Color
    /// Accent for text and glyphs (artist name, Shuffle); lifted for ≥ 3:1 contrast with `background`.
    public var accent: Color
    /// The art's vivid color, unlifted, for solid button fills (Play).
    public var fill: Color
    /// Glyph/text color to place on `fill`.
    public var onAccent: Color
    /// Slightly lifted background for cards and grouped rows.
    public var surface: Color

    /// Extracts a palette by downsampling. Pure CPU work; call off the main actor.
    public nonisolated static func extract(from image: UIImage) -> ArtworkPalette? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        func rgb(_ x: Int, _ y: Int) -> RGB {
            let i = (y * side + x) * 4
            return RGB(r: Double(pixels[i]) / 255, g: Double(pixels[i + 1]) / 255, b: Double(pixels[i + 2]) / 255)
        }

        // CGContext rows start at the top in memory: the last rows are the image's bottom edge.
        let bottom = (side - 4 ..< side).flatMap { y in (0 ..< side).map { rgb($0, y) } }
        var background = RGB.average(bottom)
        // White text needs ≥ 3:1 (large/bold text); darken until it gets there.
        while background.contrast(with: .white) < 3, background.brightness > 0.05 {
            background = background.scaled(0.9)
        }

        let all = (0 ..< side).flatMap { y in (0 ..< side).map { rgb($0, y) } }
        var accent: RGB
        if let vivid = all.filter({ $0.brightness > 0.3 }).max(by: { $0.vividness < $1.vividness }), vivid.saturation > 0.2 {
            // Average the pixels near the most vivid hue for a stable, representative color.
            let neighbors = all.filter { abs($0.hue - vivid.hue) < 0.04 && $0.saturation > 0.3 && $0.brightness > 0.3 }
            accent = RGB.average(neighbors.isEmpty ? [vivid] : neighbors).withMinimum(saturation: 0.45, brightness: 0.8)
        } else {
            // Monochrome art: neutral light accent instead of an arbitrary tint.
            accent = RGB(r: 0.92, g: 0.92, b: 0.92)
        }

        let fill = accent
        // Accent text (artist name, Shuffle) must stand out from the page: lift toward white until 3:1.
        var steps = 0
        while accent.contrast(with: background) < 3, steps < 10 {
            accent = accent.mixed(with: .white, amount: 0.18)
            steps += 1
        }

        return ArtworkPalette(
            background: background.color,
            accent: accent.color,
            fill: fill.color,
            onAccent: fill.luminance > 0.55 ? .black : .white,
            surface: background.mixed(with: .white, amount: 0.1).color
        )
    }
}

public extension Theme {
    /// This theme recolored by an artwork palette. Every token-driven component follows automatically.
    func tinted(by palette: ArtworkPalette?) -> Theme {
        guard let palette else { return self }
        var theme = self
        theme.palette.background = palette.background
        theme.palette.surface = palette.surface
        theme.palette.accent = palette.accent
        theme.palette.accentFill = palette.fill
        theme.palette.onAccent = palette.onAccent
        theme.palette.textSecondary = .white.opacity(0.7)
        return theme
    }
}

/// Loads artwork through Nuke's cache and extracts its palette off the main thread.
/// Palettes are memoized per URL so revisiting a page is instant.
public enum ArtworkPaletteLoader {
    nonisolated(unsafe) private static let cache = NSCache<NSURL, Box>()

    private final class Box {
        let palette: ArtworkPalette
        init(_ palette: ArtworkPalette) { self.palette = palette }
    }

    public static func palette(for url: URL?) async -> ArtworkPalette? {
        guard let url else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached.palette }
        guard let image = try? await ImagePipeline.shared.image(for: url) else { return nil }
        let palette = await extractInBackground(from: image)
        if let palette { cache.setObject(Box(palette), forKey: url as NSURL) }
        return palette
    }

    @concurrent private static func extractInBackground(from image: UIImage) async -> ArtworkPalette? {
        ArtworkPalette.extract(from: image)
    }
}

// MARK: - Color math

nonisolated struct RGB: Sendable, Equatable {
    var r, g, b: Double

    static let white = RGB(r: 1, g: 1, b: 1)

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    static func average(_ colors: [RGB]) -> RGB {
        guard !colors.isEmpty else { return RGB(r: 0.1, g: 0.1, b: 0.1) }
        let n = Double(colors.count)
        return RGB(r: colors.map(\.r).reduce(0, +) / n, g: colors.map(\.g).reduce(0, +) / n, b: colors.map(\.b).reduce(0, +) / n)
    }

    var brightness: Double { max(r, g, b) }
    var saturation: Double {
        let maxV = max(r, g, b), minV = min(r, g, b)
        return maxV == 0 ? 0 : (maxV - minV) / maxV
    }

    var vividness: Double { saturation * brightness }

    var hue: Double {
        let maxV = max(r, g, b), minV = min(r, g, b), delta = maxV - minV
        guard delta > 0 else { return 0 }
        var h: Double
        if maxV == r { h = (g - b) / delta } else if maxV == g { h = 2 + (b - r) / delta } else { h = 4 + (r - g) / delta }
        h /= 6
        return h < 0 ? h + 1 : h
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func scaled(_ factor: Double) -> RGB { RGB(r: r * factor, g: g * factor, b: b * factor) }

    func mixed(with other: RGB, amount: Double) -> RGB {
        RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    /// Raises saturation/brightness (keeping hue) so accents read as "colorful" on dark backgrounds.
    func withMinimum(saturation minS: Double, brightness minB: Double) -> RGB {
        let s = max(saturation, minS), v = max(brightness, minB), h = hue * 6
        let c = v * s, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r1, g1, b1): (Double, Double, Double) = switch Int(h) % 6 {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return RGB(r: r1 + m, g: g1 + m, b: b1 + m)
    }
}
