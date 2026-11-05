import CoreText
import SwiftUI

/// The launch splash: the cube over "Wavetile" over the wave (loading.svg).
///
/// The layout matches the static launch image exactly (same geometry, same outlines), so launch
/// hands off without a jump. Then the cube turns and a ripple runs through the wave, both starting
/// from their resting pose. Reduce Motion keeps everything still.
public struct SplashScreen: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        ZStack {
            theme.palette.background
            Canvas { canvas, size in
                Lockup.drawWord(in: &canvas, center: CGPoint(x: size.width / 2, y: size.height / 2), color: theme.palette.accent)
            }
            GeometryReader { proxy in
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                WavetileMark(isAnimating: true, size: Lockup.cubeSize)
                    .position(x: center.x, y: center.y + Lockup.cubeY)
                WaveMark(isAnimating: true, width: Lockup.waveWidth, lineWidth: WavetileMark.strokeWidth)
                    .position(x: center.x, y: center.y + Lockup.waveY)
            }
        }
        .ignoresSafeArea()
        // One modal element, so VoiceOver (and UI tests) can't reach the app it covers; hiding the
        // app instead doesn't reach its UIKit-backed tab and navigation views.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wavetile")
        .accessibilityAddTraits(.isModal)
    }
}

/// The cube over "Wavetile" over the wave, from loading.svg (402 × 874): sizes and positions
/// shared with the launch image (`App/Assets.xcassets/LaunchSplash`, rendered with the same numbers).
/// Everything is centered horizontally; vertical offsets are from the screen's center.
public enum Lockup {
    /// Puts the mark's tile at 29pt, as drawn.
    public static let cubeSize: CGFloat = 36.25
    static let cubeY: CGFloat = -105.5
    /// The word's baseline.
    static let wordY: CGFloat = -10
    /// The wave's baseline; wave.svg at its own size.
    static let waveY: CGFloat = 53.9
    static let waveWidth: CGFloat = 92

    static func drawWord(in canvas: inout GraphicsContext, center: CGPoint, color: Color) {
        canvas.fill(word.offsetBy(dx: center.x, dy: center.y + wordY), with: .color(color))
    }

    /// "Wavetile" in the wordmark face as one path, centered on 0 with its baseline at 0.
    private static let word: Path = {
        BrandFont.register()
        // Sized to loading.svg's 40.9pt cap height.
        let reference = CTFontCreateWithName(BrandFont.regularName as CFString, 100, nil)
        let font = CTFontCreateWithName(BrandFont.regularName as CFString, 100 * 40.926 / CTFontGetCapHeight(reference), nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .ligature: 0]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Wavetile", attributes: attributes))
        var path = Path()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                // Core Text is y-up; flip into view space.
                var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: position.x, ty: 0)
                if let glyphPath = CTFontCreatePathForGlyph(font, glyph, &transform) {
                    path.addPath(Path(glyphPath))
                }
            }
        }
        // Centered on the ink, as drawn.
        return path.offsetBy(dx: -path.boundingRect.midX, dy: 0)
    }()
}

#Preview {
    SplashScreen()
}
