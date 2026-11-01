import CoreText
import SwiftUI
import UIKit

/// The launch splash: the cube over "Wavetile", centered on a field of faint wave lines.
///
/// The lockup matches the static launch image exactly (same geometry, glyphs from the same font),
/// so launch hands off without a jump. The launch image carries the waves too, so they're there
/// from the first frame; then the cube turns and the waves drift sideways, just enough to feel
/// alive. Reduce Motion keeps everything still.
public struct SplashScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now

    public init() {}

    public var body: some View {
        ZStack {
            theme.palette.background
            TimelineView(.animation(paused: reduceMotion)) { context in
                let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(start)
                Canvas { canvas, size in
                    WaveField.draw(in: &canvas, size: size, elapsed: elapsed, color: theme.palette.accent)
                    Lockup.drawWord(in: &canvas, center: CGPoint(x: size.width / 2, y: size.height / 2), color: theme.palette.accent)
                }
            }
            GeometryReader { proxy in
                WavetileMark(isAnimating: true, size: Lockup.cubeSize)
                    .position(Lockup.cubeCenter(in: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Faint rows of waves filling the screen, drifting sideways slowly. Laid out from the screen's
/// center, as the launch image is (it's centered), so the first frame lines up on every iPhone.
enum WaveField {
    static let rowSpacing: CGFloat = 17
    /// Half a wave (one lobe) and its height.
    static let lobe: CGFloat = 20, amplitude: CGFloat = 2.6
    /// The icons' and the cube's stroke.
    static let lineWidth = WavetileMark.strokeWidth
    static let opacity = 0.09
    /// Points per second.
    static let drift: CGFloat = 5
    /// How far each row sits out of step with the one above it.
    static let rowOffset: CGFloat = 7

    static func draw(in canvas: inout GraphicsContext, size: CGSize, elapsed: TimeInterval, color: Color) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let period = lobe * 2, control = amplitude / 0.75
        let rowsEachSide = Int(size.height / 2 / rowSpacing) + 1
        var path = Path()
        for row in -rowsEachSide...rowsEachSide {
            let y = center.y + CGFloat(row) * rowSpacing
            let shift = CGFloat(elapsed) * drift + CGFloat(row) * rowOffset
            // First crest start at or left of the screen's left edge, in phase with the center.
            let phase = (shift.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period)
            var x = center.x - phase - (center.x / period).rounded(.up) * period - period
            var up = true
            path.move(to: CGPoint(x: x, y: y))
            while x < size.width + period {
                let dy = up ? -control : control
                path.addCurve(
                    to: CGPoint(x: x + lobe, y: y),
                    control1: CGPoint(x: x + lobe / 3, y: y + dy),
                    control2: CGPoint(x: x + lobe * 2 / 3, y: y + dy)
                )
                x += lobe
                up.toggle()
            }
        }
        canvas.stroke(path, with: .color(color.opacity(opacity)), lineWidth: lineWidth)
    }
}

/// The cube over "Wavetile": sizes and positions shared with the launch image
/// (`App/Assets.xcassets/LaunchMark`, rendered with the same numbers).
public enum Lockup {
    public static let cubeSize: CGFloat = 36
    public static let gap: CGFloat = 10
    public static let wordWidth: CGFloat = 132

    /// From the cube's top to the word's baseline; centered on the screen.
    private static var height: CGFloat { cubeSize + gap + Glyphs.shared.capHeight }

    static func cubeCenter(in center: CGPoint) -> CGPoint {
        CGPoint(x: center.x, y: center.y - height / 2 + cubeSize / 2)
    }

    static func drawWord(in canvas: inout GraphicsContext, center: CGPoint, color: Color) {
        let baseline = center.y + height / 2
        canvas.fill(Glyphs.shared.path.offsetBy(dx: center.x, dy: baseline), with: .color(color))
    }

    /// "Wavetile" in the display face as one path, centered horizontally on 0 with its baseline at 0.
    private struct Glyphs: @unchecked Sendable {
        static let shared = Glyphs()
        let path: Path
        let capHeight: CGFloat

        private init() {
            BrandFont.register()
            let reference = Self.line(size: 100)
            let size = 100 * Lockup.wordWidth / max(CGFloat(CTLineGetTypographicBounds(reference.line, nil, nil, nil)), 1)
            let (line, font) = Self.line(size: size)
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            capHeight = CTFontGetCapHeight(font)
            var path = Path()
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                for (glyph, position) in zip(glyphs, positions) {
                    // Core Text is y-up; flip into view space.
                    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: position.x - width / 2, ty: 0)
                    if let glyphPath = CTFontCreatePathForGlyph(font, glyph, &transform) {
                        path.addPath(Path(glyphPath))
                    }
                }
            }
            self.path = path
        }

        private static func line(size: CGFloat) -> (line: CTLine, font: CTFont) {
            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: BrandFont.displayFamily,
                .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold],
            ])
            let font = UIFont(descriptor: descriptor, size: size) as CTFont
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .ligature: 0]
            return (CTLineCreateWithAttributedString(NSAttributedString(string: "Wavetile", attributes: attributes)), font)
        }
    }
}

#Preview {
    SplashScreen()
}
