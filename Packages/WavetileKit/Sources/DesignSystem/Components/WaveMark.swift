import SwiftUI

/// The Wavetile mark: one hand-drawn line of six lobes (wave.svg, 92 × 15).
///
/// Static by default. Animating, a soft ripple travels left to right through the lobes, swelling
/// and settling each in turn like a signal passing through; it starts from the resting line, so
/// it picks up from the launch image without a jump. Reduce Motion holds the resting line.
public struct WaveMark: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let isAnimating: Bool
    private let width: CGFloat
    private let strength: Double
    private let color: Color?

    /// `strength` is how far the ripple swells each lobe (0.32 = 32%); `color` defaults to the accent.
    public init(isAnimating: Bool = false, width: CGFloat = 92, strength: Double = 0.32, color: Color? = nil) {
        self.isAnimating = isAnimating
        self.width = width
        self.strength = strength
        self.color = color
    }

    private var active: Bool { isAnimating && !reduceMotion }

    public var body: some View {
        TimelineView(.animation(paused: !active)) { context in
            let elapsed = active ? context.date.timeIntervalSince(Self.epoch) : 0
            Canvas { canvas, size in
                let swell = Self.swell(at: elapsed, strength: strength * Self.rampIn(elapsed))
                Self.draw(in: &canvas, width: size.width, center: CGPoint(x: size.width / 2, y: size.height / 2), swell: swell, color: color ?? theme.palette.accent)
            }
        }
        // Room above and below for the ripple's tallest swell.
        .frame(width: width, height: Self.height(forWidth: width) * (1 + strength))
        .accessibilityHidden(true)
    }

    /// Shared start time, so every mark on screen ripples in step.
    static let epoch = Date()

    /// Seconds for the ripple to cross the line once.
    public static let period = 1.6

    public static func height(forWidth width: CGFloat) -> CGFloat {
        WaveShape.viewBox.height * width / WaveShape.viewBox.width
    }

    public static func lineWidth(forWidth width: CGFloat) -> CGFloat {
        WaveShape.lineWidth * width / WaveShape.viewBox.width
    }

    /// Eases the ripple in from the resting line over the first 0.4 s.
    static func rampIn(_ elapsed: TimeInterval) -> Double {
        let x = min(1, max(0, elapsed / 0.4))
        return x * x * (3 - 2 * x)
    }

    /// Per-lobe height multipliers (1 is the drawn shape): a sine pulse moving along the lobes.
    public static func swell(at elapsed: TimeInterval, period: Double = period, strength: Double) -> [CGFloat] {
        (0..<WaveShape.lobes.count).map { index in
            let phase = 2 * .pi * (elapsed / period) - Double(index) * 0.75
            return 1 + CGFloat(strength * sin(phase))
        }
    }

    /// The wave's path, `width` wide, with its baseline centered on `center`.
    public static func path(width: CGFloat, center: CGPoint, swell: [CGFloat] = []) -> Path {
        let height = height(forWidth: width)
        let origin = CGPoint(x: center.x - width / 2, y: center.y - height / 2)
        return WaveShape(swell: swell).path(in: CGRect(origin: origin, size: CGSize(width: width, height: height)))
    }

    /// Strokes the wave into a canvas.
    public static func draw(in canvas: inout GraphicsContext, width: CGFloat, center: CGPoint, swell: [CGFloat], color: Color) {
        canvas.stroke(
            path(width: width, center: center, swell: swell),
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth(forWidth: width), lineCap: .round)
        )
    }
}

/// wave.svg as a shape. Each lobe is one cubic from baseline to baseline; `swell` scales how far
/// its control points reach from the baseline. The baseline sits at the rect's vertical middle.
nonisolated struct WaveShape: Shape {
    var swell: [CGFloat] = []

    static let viewBox = CGSize(width: 92, height: 15)
    static let lineWidth: CGFloat = 2
    static let baseline: CGFloat = 7.9

    /// End x, the two control x's, and the control y, straight from the SVG path.
    static let lobes: [(end: CGFloat, c1: CGFloat, c2: CGFloat, y: CGFloat)] = [
        (16, 6, 11, -1.3),
        (31, 20.5109, 25.5109, 15.3),
        (46, 36, 41, 0.5),
        (61, 51.2703, 56.2703, 16.1),
        (76, 66, 71, -0.3),
        (91, 80.6341, 85.6341, 14.9),
    ]

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / Self.viewBox.width
        let midY = rect.midY
        let point = { (x: CGFloat, y: CGFloat) in
            CGPoint(x: rect.minX + x * scale, y: midY + (y - Self.baseline) * scale)
        }
        var path = Path()
        path.move(to: point(1, Self.baseline))
        for (index, lobe) in Self.lobes.enumerated() {
            let reach = (lobe.y - Self.baseline) * (swell.indices.contains(index) ? swell[index] : 1)
            path.addCurve(
                to: point(lobe.end, Self.baseline),
                control1: point(lobe.c1, Self.baseline + reach),
                control2: point(lobe.c2, Self.baseline + reach)
            )
        }
        return path
    }
}

#Preview {
    VStack(spacing: 48) {
        WaveMark(isAnimating: true, width: 180)
        WaveMark(width: 104)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.dark.palette.background)
}
