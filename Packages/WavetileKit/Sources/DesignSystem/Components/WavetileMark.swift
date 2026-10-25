import SwiftUI

/// The Wavetile mark: a rounded tile with three edges running from its center, read as a cube.
///
/// At rest the edges hit the top middle, right middle and bottom-left corner, matching the app
/// icon. While animating, all three slide a quarter turn around the frame at a time, so the cube
/// appears to turn to a new corner. Reduce Motion holds the resting pose.
public struct WavetileMark: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let isAnimating: Bool
    private let size: CGFloat

    public init(isAnimating: Bool = false, size: CGFloat = 96) {
        self.isAnimating = isAnimating
        self.size = size
    }

    private var active: Bool { isAnimating && !reduceMotion }

    public var body: some View {
        TimelineView(.animation(paused: !active)) { context in
            let start = Self.epoch
            Canvas { canvas, canvasSize in
                let turn = active ? Self.turn(at: context.date.timeIntervalSince(start)) : 0
                Self.draw(in: &canvas, size: canvasSize, turn: turn, color: theme.palette.accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Shared start time, so every mark on screen turns in step.
    private static let epoch = Date()

    /// Seconds spent moving, then resting, per quarter turn.
    public static let move = 0.7
    public static let hold = 0.5

    /// Turn position in quarter turns: whole numbers are rest poses.
    static func turn(at elapsed: TimeInterval) -> Double {
        let period = move + hold
        let step = (elapsed / period).rounded(.down)
        let within = elapsed - step * period
        return step + ease(min(1, within / move))
    }

    private static func ease(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    // Geometry on a 100-unit grid, matching the loader prototype.
    private static let lineWidth: CGFloat = 11
    private static let frameRect = CGRect(x: 10, y: 10, width: 80, height: 80)
    private static let frameRadius: CGFloat = 8
    private static let hubRadius: CGFloat = 5.5
    /// The square the edges end on, and where each edge starts along it (1 per side, clockwise from top-left).
    private static let low: CGFloat = 12, high: CGFloat = 88
    private static let restPositions: [Double] = [0.5, 1.5, 3]

    private static func pointOnFrame(_ position: Double) -> CGPoint {
        let s = (position.truncatingRemainder(dividingBy: 4) + 4).truncatingRemainder(dividingBy: 4)
        let side = Int(s), f = CGFloat(s - Double(side)), length = high - low
        switch side {
        case 0: return CGPoint(x: low + length * f, y: low)
        case 1: return CGPoint(x: high, y: low + length * f)
        case 2: return CGPoint(x: high - length * f, y: high)
        default: return CGPoint(x: low, y: high - length * f)
        }
    }

    /// Draws the mark scaled to fit `size`. Also used to render the app icon and launch image.
    public static func draw(in canvas: inout GraphicsContext, size: CGSize, turn: Double, color: Color) {
        let scale = min(size.width, size.height) / 100
        canvas.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
        canvas.scaleBy(x: scale, y: scale)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
        let center = CGPoint(x: 50, y: 50)

        var rays = Path()
        for position in restPositions {
            rays.move(to: center)
            rays.addLine(to: pointOnFrame(position + turn))
        }
        canvas.stroke(rays, with: .color(color), style: style)
        canvas.fill(
            Path(ellipseIn: CGRect(x: 50 - hubRadius, y: 50 - hubRadius, width: hubRadius * 2, height: hubRadius * 2)),
            with: .color(color)
        )
        canvas.stroke(Path(roundedRect: frameRect, cornerRadius: frameRadius), with: .color(color), style: style)
    }
}

/// Branded loading indicator: the turning mark, sized for content areas.
public struct LoadingMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public var body: some View {
        WavetileMark(isAnimating: true, size: size)
            .accessibilityElement()
            .accessibilityLabel("Loading")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    VStack(spacing: 40) {
        WavetileMark(isAnimating: true)
        LoadingMark()
        WavetileMark()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.wavetile.palette.background)
}
