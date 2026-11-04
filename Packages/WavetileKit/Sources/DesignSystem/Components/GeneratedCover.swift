import SwiftUI
import UIKit

/// Generated cover art for playlists and collections: a few modernist shapes in the brand's tan
/// and near-black, lit by one light and stippled like an engraving, with registration marks and a mono
/// code. The seed (item ID + shuffle count) decides everything, so a cover is the same on every
/// launch and device until it's shuffled. Ported from `scratch/cover-lab.html`, which is the
/// place to experiment before changing anything here.
///
/// Any change to the palettes, layouts or their order changes existing covers. `version` is part
/// of every seed; bump it when that's intended, so it's a deliberate one-time reshuffle.
nonisolated public enum CoverArt {
    public static let version = "v1"

    /// The seed for an item's cover. `shuffle` is how many times the user has asked for a new one.
    public static func seed(id: String, shuffle: Int = 0) -> String {
        "\(version)|\(id)|\(shuffle)"
    }

    /// The cover's field color, drawn while the cover renders so it fades in from its own color.
    public static func background(seed: String) -> Color {
        Color(cgColor: Spec(seed: seed).palette.background)
    }

    /// The cover at `pixels` square, from the cache or freshly rendered. `scale` is the screen
    /// scale, so dots and marks stay a legible size in points on small tiles.
    @concurrent public static func image(seed: String, pixels: Int, scale: CGFloat) async -> CGImage? {
        renderSync(seed: seed, pixels: pixels, scale: scale)
    }

    /// Already-rendered cover, if any, so a view can show it on its first frame.
    public static func cached(seed: String, pixels: Int) -> CGImage? {
        cache.object(forKey: key(seed, pixels))
    }

    public static func renderSync(seed: String, pixels: Int, scale: CGFloat) -> CGImage? {
        guard pixels > 0 else { return nil }
        if let hit = cached(seed: seed, pixels: pixels) { return hit }
        let image = Renderer(spec: Spec(seed: seed), size: pixels, scale: scale).draw()
        if let image { cache.setObject(image, forKey: key(seed, pixels), cost: pixels * pixels * 4) }
        return image
    }

    private nonisolated(unsafe) static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 64 << 20
        return cache
    }()

    private static func key(_ seed: String, _ pixels: Int) -> NSString { "\(seed)@\(pixels)" as NSString }
}

// MARK: - Palettes

nonisolated extension CoverArt {
    struct Palette {
        let name: String
        let background: CGColor
        let fills: [CGColor]
    }

    /// The brand's two: Wavetile (tan marks on the dark canvas) and Tan (dark marks on tan), each
    /// with a quieter second fill.
    static let palettes: [Palette] = [
        palette("Wavetile", Theme.CoverPalette.ink, Theme.CoverPalette.tan, Theme.CoverPalette.inkSecondFill),
        palette("Tan", Theme.CoverPalette.tan, Theme.CoverPalette.ink, Theme.CoverPalette.tanSecondFill),
    ]

    /// Dot inks: the brand tan for light dots, near-black for dark ones.
    static let lightInk = rgb(Theme.CoverPalette.tan)
    static let darkInk = rgb(Theme.CoverPalette.darkDot)

    private static func palette(_ name: String, _ background: UInt32, _ a: UInt32, _ b: UInt32) -> Palette {
        Palette(name: name, background: rgb(background), fills: [rgb(a), rgb(b)])
    }

    static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Relative luminance (WCAG).
    static func luminance(_ color: CGColor) -> Double {
        let c = (color.components ?? [0, 0, 0]).prefix(3).map { v -> Double in
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }

    static func contrastInk(on color: CGColor) -> CGColor {
        luminance(color) > 0.22 ? darkInk : lightInk
    }
}

// MARK: - Randomness

nonisolated extension CoverArt {
    /// cyrb53 folded to 32 bits: a fast, well-mixed string hash (same as the lab).
    static func hash(_ string: String) -> UInt32 {
        var h1: UInt32 = 0xDEADBEEF, h2: UInt32 = 0x41C6CE57
        for unit in string.utf16 {
            let c = UInt32(unit)
            h1 = (h1 ^ c) &* 2_654_435_761
            h2 = (h2 ^ c) &* 1_597_334_677
        }
        h1 = ((h1 ^ (h1 >> 16)) &* 2_246_822_507) ^ ((h2 ^ (h2 >> 13)) &* 3_266_489_909)
        h2 = ((h2 ^ (h2 >> 16)) &* 2_246_822_507) ^ ((h1 ^ (h1 >> 13)) &* 3_266_489_909)
        return h1 ^ h2
    }

    /// mulberry32: tiny seeded PRNG, uniform in [0, 1).
    struct Random {
        private var state: UInt32
        init(_ seed: UInt32) { state = seed }

        mutating func next() -> Double {
            state = state &+ 0x6D2B_79F5
            var t = (state ^ (state >> 15)) &* (1 | state)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }

        mutating func range(_ a: Double, _ b: Double) -> Double { a + next() * (b - a) }
        mutating func pick<T>(_ items: [T]) -> T { items[min(items.count - 1, Int(next() * Double(items.count)))] }
        mutating func int(_ n: Int) -> Int { min(n - 1, Int(next() * Double(n))) }
    }

    /// Snaps to a 12-column grid (or `n`), for the modernist alignment.
    static func snap(_ v: Double, _ n: Double = 12) -> Double { (v * n).rounded() / n }
}

// MARK: - Shapes

nonisolated extension CoverArt {
    /// One shape in the unit square (y down). Angles are radians, increasing clockwise on screen.
    enum Shape {
        case circle(cx: Double, cy: Double, r: Double)
        /// A disc clipped to the angles `a0...a1`: halves (π) and quarters (π/2).
        case wedge(cx: Double, cy: Double, r: Double, a0: Double, a1: Double)
        case triangle(SIMD2<Double>, SIMD2<Double>, SIMD2<Double>)
        case rect(x: Double, y: Double, w: Double, h: Double)

        var isFlat: Bool {
            switch self {
            case .triangle, .rect: true
            case .circle, .wedge: false
            }
        }

        var bounds: (x0: Double, y0: Double, x1: Double, y1: Double) {
            switch self {
            case let .circle(cx, cy, r), let .wedge(cx, cy, r, _, _):
                return (cx - r, cy - r, cx + r, cy + r)
            case let .triangle(a, b, c):
                return (min(a.x, b.x, c.x), min(a.y, b.y, c.y), max(a.x, b.x, c.x), max(a.y, b.y, c.y))
            case let .rect(x, y, w, h):
                return (x, y, x + w, y + h)
            }
        }

        func contains(_ x: Double, _ y: Double) -> Bool {
            switch self {
            case let .circle(cx, cy, r):
                return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r
            case let .wedge(cx, cy, r, a0, a1):
                let dx = x - cx, dy = y - cy
                guard dx * dx + dy * dy <= r * r else { return false }
                let twoPi = 2 * Double.pi
                let offset = (atan2(dy, dx) - a0).truncatingRemainder(dividingBy: twoPi)
                return (offset < 0 ? offset + twoPi : offset) <= a1 - a0
            case let .triangle(a, b, c):
                func side(_ p: SIMD2<Double>, _ q: SIMD2<Double>, _ r: SIMD2<Double>) -> Double {
                    (p.x - r.x) * (q.y - r.y) - (q.x - r.x) * (p.y - r.y)
                }
                let p = SIMD2(x, y), d1 = side(p, a, b), d2 = side(p, b, c), d3 = side(p, c, a)
                return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0))
            case let .rect(rx, ry, w, h):
                return x >= rx && x <= rx + w && y >= ry && y <= ry + h
            }
        }

        /// How lit the surface is at (x, y), 0...1. Discs shade as spheres, bars as rods (a
        /// cylinder across the short side), triangles as a ramp.
        func tone(_ x: Double, _ y: Double, light l: SIMD3<Double>) -> Double {
            switch self {
            case let .circle(cx, cy, r), let .wedge(cx, cy, r, _, _):
                let nx = (x - cx) / r, ny = (y - cy) / r
                let nz = max(0, 1 - nx * nx - ny * ny).squareRoot()
                return max(0, nx * l.x + ny * l.y + nz * l.z)
            case .triangle:
                let b = bounds
                let u = (x - (b.x0 + b.x1) / 2) * l.x + (y - (b.y0 + b.y1) / 2) * l.y
                let span = max(b.x1 - b.x0, b.y1 - b.y0)
                return min(1, max(0, 0.5 + u / span * 1.4))
            case let .rect(rx, ry, w, h):
                let horizontal = w >= h
                let t = horizontal ? (y - ry) / h * 2 - 1 : (x - rx) / w * 2 - 1
                let nz = max(0, 1 - t * t).squareRoot()
                return max(0, (horizontal ? t * l.y : t * l.x) + nz * l.z)
            }
        }

        /// A random point on the outline (the arc for discs) and its outward normal.
        func edgePoint(_ rand: inout Random) -> (x: Double, y: Double, nx: Double, ny: Double) {
            switch self {
            case let .circle(cx, cy, r):
                let a = rand.next() * 2 * .pi
                return (cx + cos(a) * r, cy + sin(a) * r, cos(a), sin(a))
            case let .wedge(cx, cy, r, a0, a1):
                let a = a0 + rand.next() * (a1 - a0)
                return (cx + cos(a) * r, cy + sin(a) * r, cos(a), sin(a))
            case let .triangle(a, b, c):
                let points = [a, b, c], i = rand.int(3), p = points[i], q = points[(i + 1) % 3], t = rand.next()
                var n = SIMD2(q.y - p.y, -(q.x - p.x))
                n /= max(1e-9, (n * n).sum().squareRoot())
                let e = p + (q - p) * t, centroid = (a + b + c) / 3
                if ((e - centroid) * n).sum() < 0 { n = -n }
                return (e.x, e.y, n.x, n.y)
            case let .rect(x, y, w, h):
                let p = rand.next() * 2 * (w + h)
                if p < w { return (x + p, y, 0, -1) }
                if p < w + h { return (x + w, y + p - w, 1, 0) }
                if p < 2 * w + h { return (x + p - w - h, y + h, 0, 1) }
                return (x, y + p - 2 * w - h, -1, 0)
            }
        }

        func path(size s: Double) -> CGPath {
            switch self {
            case let .circle(cx, cy, r):
                return CGPath(ellipseIn: CGRect(x: (cx - r) * s, y: (cy - r) * s, width: 2 * r * s, height: 2 * r * s), transform: nil)
            case let .wedge(cx, cy, r, a0, a1):
                let center = CGPoint(x: cx * s, y: cy * s)
                let path = UIBezierPath()
                path.move(to: center)
                path.addArc(withCenter: center, radius: r * s, startAngle: a0, endAngle: a1, clockwise: true)
                path.close()
                return path.cgPath
            case let .triangle(a, b, c):
                let path = CGMutablePath()
                path.addLines(between: [a, b, c].map { CGPoint(x: $0.x * s, y: $0.y * s) })
                path.closeSubpath()
                return path
            case let .rect(x, y, w, h):
                return CGPath(rect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), transform: nil)
            }
        }
    }

    struct Layer {
        let shape: Shape
        /// Index into the palette's fills.
        let fill: Int
    }
}

// MARK: - Layouts

nonisolated extension CoverArt {
    /// Seven layouts, each 1–4 shapes snapped to the grid.
    enum Layout: String, CaseIterable {
        case sun, halves, truchet, arches, diagonal, dotgrid, pills

        /// Short code for the overlay (e.g. `TRU.04`).
        var code: String { String(rawValue.prefix(3)).uppercased() }

        func layers(_ r: inout Random) -> [Layer] {
            switch self {
            case .sun:
                let radius = snap(r.range(0.2, 0.34))
                let cx = snap(r.range(radius + 0.08, 1 - radius - 0.08)), cy = snap(r.range(radius + 0.08, 1 - radius - 0.12))
                var layers = [Layer(shape: .circle(cx: cx, cy: cy, r: radius), fill: 0)]
                if r.next() < 0.6 {
                    // A horizon bar behind it.
                    let y = snap(r.range(0.72, 0.86)), h = snap(r.range(0.04, 0.12), 24)
                    layers.insert(Layer(shape: .rect(x: 0, y: y, w: 1, h: h), fill: 1), at: 0)
                }
                return layers
            case .halves:
                let radius = snap(r.range(0.22, 0.32)), gap = snap(r.range(0, 0.08), 24)
                let vertical = r.next() < 0.5, off = snap(r.range(-0.1, 0.1))
                if vertical {
                    return [
                        Layer(shape: .wedge(cx: 0.5 - gap, cy: 0.5 + off, r: radius, a0: .pi / 2, a1: .pi * 1.5), fill: 0),
                        Layer(shape: .wedge(cx: 0.5 + gap, cy: 0.5 - off, r: radius, a0: -.pi / 2, a1: .pi / 2), fill: 1),
                    ]
                }
                return [
                    Layer(shape: .wedge(cx: 0.5 + off, cy: 0.5 - gap, r: radius, a0: .pi, a1: .pi * 2), fill: 0),
                    Layer(shape: .wedge(cx: 0.5 - off, cy: 0.5 + gap, r: radius, a0: 0, a1: .pi), fill: 1),
                ]
            case .truchet:
                // Quarter discs pivoting on the corners of a 2×2 grid.
                let n = 2, margin = 0.1, cell = (1 - 2 * margin) / Double(n)
                var layers: [Layer] = []
                for i in 0..<n {
                    for j in 0..<n {
                        let isLast = i == n - 1 && j == n - 1
                        if r.next() < 0.18, !(layers.isEmpty && isLast) { continue }
                        let k = r.int(4)
                        let px = margin + Double(i + (k == 1 || k == 2 ? 1 : 0)) * cell
                        let py = margin + Double(j + (k >= 2 ? 1 : 0)) * cell
                        let a0 = Double(k) * .pi / 2
                        layers.append(Layer(shape: .wedge(cx: px, cy: py, r: cell, a0: a0, a1: a0 + .pi / 2), fill: r.next() < 0.75 ? 0 : 1))
                    }
                }
                return layers
            case .arches:
                let n = r.pick([2, 3, 4]), cx = snap(r.range(0.3, 0.7)), base = snap(r.range(0.7, 0.9))
                let radius = snap(r.range(0.3, 0.42)), step = radius / Double(n)
                return (0..<n).map { i in
                    Layer(shape: .wedge(cx: cx, cy: base, r: radius - Double(i) * step, a0: .pi, a1: .pi * 2), fill: i % 2)
                }
            case .diagonal:
                let corner = r.int(4)
                let p: [SIMD2<Double>] = [[0, 0], [1, 0], [1, 1], [0, 1]]
                let radius = snap(r.range(0.14, 0.22))
                return [
                    Layer(shape: .triangle(p[corner], p[(corner + 1) % 4], p[(corner + 3) % 4]), fill: 1),
                    Layer(shape: .circle(cx: snap(r.range(0.3, 0.7)), cy: snap(r.range(0.3, 0.7)), r: radius), fill: 0),
                ]
            case .dotgrid:
                let n = 2, margin = 0.14, cell = (1 - 2 * margin) / Double(n), radius = cell * r.range(0.3, 0.46)
                let hot = r.int(n * n)
                var layers: [Layer] = []
                for i in 0..<(n * n) {
                    if i != hot, r.next() < 0.2 { continue }
                    let x = margin + (Double(i % n) + 0.5) * cell, y = margin + (Double(i / n) + 0.5) * cell
                    layers.append(Layer(shape: .circle(cx: x, cy: y, r: i == hot ? cell * 0.48 : radius), fill: i == hot ? 0 : 1))
                }
                return layers
            case .pills:
                // A column of half discs, like a stacked capsule.
                let n = r.pick([2, 3, 4]), w = snap(r.range(0.28, 0.46)), x = snap(r.range(0.15, 0.85 - w)), h = 0.76 / Double(n)
                return (0..<n).map { i in
                    let y = 0.12 + Double(i) * h, flip = (i + (r.next() < 0.5 ? 0 : 1)) % 2 == 1
                    return Layer(
                        shape: .wedge(cx: x + w / 2, cy: flip ? y : y + h, r: w / 2, a0: flip ? 0 : .pi, a1: flip ? .pi : .pi * 2),
                        fill: i % 2
                    )
                }
            }
        }
    }
}

// MARK: - Spec

nonisolated extension CoverArt {
    /// Everything a seed decides: palette, layout, light, and the shapes.
    struct Spec {
        let seed: UInt32
        let palette: Palette
        let fills: [CGColor]
        let layout: Layout
        /// Unit light vector, y down, mostly from above.
        let light: SIMD3<Double>
        let layers: [Layer]

        init(seed string: String) {
            seed = CoverArt.hash(string)
            var r = Random(seed)
            palette = r.pick(CoverArt.palettes)
            layout = r.pick(Layout.allCases)
            let azimuth = r.range(.pi * 1.05, .pi * 1.95), elevation = r.range(0.25, 0.7)
            light = SIMD3(cos(elevation) * cos(azimuth), cos(elevation) * sin(azimuth), sin(elevation))
            fills = r.next() < 0.3 ? palette.fills.reversed() : palette.fills
            var shapeRandom = Random(seed ^ 0x9E37_79B9)
            layers = layout.layers(&shapeRandom)
        }
    }
}

// MARK: - Rendering

nonisolated extension CoverArt {
    /// The lab's defaults: dot gap (unit square), dot size per 1000px, tone exponent, how much
    /// the light shades (vs. flat), background grain, stray dust count and reach.
    struct Style {
        var spacing = 0.0066
        var dotSize = 1.35
        var contrast = 0.9
        var lightStrength = 0.51
        var grain = 0.05
        var stray = 500.0
        var dustReach = 0.06
    }

    struct Renderer {
        let spec: Spec
        let size: Int
        let scale: CGFloat
        var style = Style()

        func draw() -> CGImage? {
            let s = Double(size)
            // Small tiles keep dots at least 0.35pt and widen the gap with them, so the texture
            // stays visible instead of turning into sub-pixel noise.
            let dotRadius = max(style.dotSize * s / 1000, 0.35 * Double(scale))
            let spacing = max(style.spacing, dotRadius * 5.6 / s)

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
            let image = renderer.image { context in
                let cg = context.cgContext
                var rand = Random(spec.seed ^ 0x51ED_270B)
                var dots = DotBatch(scale: s, radius: dotRadius)

                cg.setFillColor(spec.palette.background)
                cg.fill(CGRect(x: 0, y: 0, width: s, height: s))

                // Grain on the field.
                let backgroundInk = CoverArt.contrastInk(on: spec.palette.background)
                stipple(&rand, bounds: (0, 0, 1, 1), spacing: spacing * 1.4, budget: 3, density: { _, _ in style.grain }) {
                    dots.add($0, $1, $2)
                }
                dots.fill(cg, backgroundInk)

                for layer in spec.layers {
                    let shape = layer.shape, fill = spec.fills[layer.fill]
                    cg.addPath(shape.path(size: s))
                    cg.setFillColor(fill)
                    cg.fillPath()

                    // Dots mean light when they're lighter than the fill, shadow when darker.
                    let ink = CoverArt.contrastInk(on: fill)
                    let inkIsLight = CoverArt.luminance(ink) > CoverArt.luminance(fill)
                    stipple(&rand, bounds: shape.bounds, spacing: spacing, budget: 7, density: { x, y in
                        guard shape.contains(x, y) else { return 0 }
                        let lit = (1 - style.lightStrength) + style.lightStrength * (0.08 + 0.92 * shape.tone(x, y, light: spec.light))
                        return pow(max(0, inkIsLight ? lit : 1 - lit), style.contrast)
                    }) { dots.add($0, $1, $2) }
                    dots.fill(cg, ink)

                    // Dust kicked off the outline in the shape's color, heavier on the lit side.
                    let count = Int(style.stray * (shape.isFlat ? 0.6 : 1) / max(1, Double(spec.layers.count).squareRoot()))
                    for _ in 0..<count {
                        let e = shape.edgePoint(&rand), d = -log(1 - rand.next()) * style.dustReach
                        let x = e.x + e.nx * d, y = e.y + e.ny * d
                        guard (0...1).contains(x), (0...1).contains(y), !shape.contains(x, y) else { continue }
                        let facing = 0.5 + 0.5 * max(0, e.nx * spec.light.x + e.ny * spec.light.y)
                        guard rand.next() <= facing else { continue }
                        dots.add(x, y, 0.7 + rand.next() * 0.4)
                    }
                    dots.fill(cg, fill)
                }

                drawOverlay(cg, size: s, ink: backgroundInk)
            }
            return image.cgImage
        }

        /// Registration marks in the corners; the seed code and layout code along the bottom on
        /// covers big enough to read them.
        private func drawOverlay(_ cg: CGContext, size s: Double, ink: CGColor) {
            let hair = max(1, s / 1000) * 1.2, margin = s * 0.045, arm = s * 0.018
            cg.setAlpha(0.7)
            cg.setStrokeColor(ink)
            cg.setLineWidth(hair)
            for (x, y) in [(margin, margin), (s - margin, margin), (margin, s - margin), (s - margin, s - margin)] {
                cg.move(to: CGPoint(x: x - arm, y: y))
                cg.addLine(to: CGPoint(x: x + arm, y: y))
                cg.move(to: CGPoint(x: x, y: y - arm))
                cg.addLine(to: CGPoint(x: x, y: y + arm))
            }
            cg.strokePath()

            guard s / Double(scale) >= 200 else { return }
            let hex = String(spec.seed, radix: 16, uppercase: true)
            let code = String(repeating: "0", count: max(0, 8 - hex.count)) + hex
            let fontSize = (s * 0.026).rounded()
            let font = UIFont(name: BrandFont.monoName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(cgColor: ink).withAlphaComponent(0.7)]
            let baseline = s - margin + s * 0.009
            let left = NSAttributedString(string: "WT/\(code.prefix(4))·\(code.suffix(4))", attributes: attributes)
            let right = NSAttributedString(string: "\(spec.layout.code).\(String(format: "%02d", spec.layers.count))", attributes: attributes)
            cg.setAlpha(1)
            left.draw(at: CGPoint(x: margin + arm * 1.6, y: baseline - font.ascender))
            right.draw(at: CGPoint(x: s - margin - arm * 1.6 - right.size().width, y: baseline - font.ascender))
        }
    }

    /// Dots collected into one path per color, then filled once.
    struct DotBatch {
        let scale: Double
        let radius: Double
        private var path = CGMutablePath()

        init(scale: Double, radius: Double) {
            self.scale = scale
            self.radius = radius
        }

        mutating func add(_ x: Double, _ y: Double, _ size: Double) {
            let r = radius * size
            path.addEllipse(in: CGRect(x: x * scale - r, y: y * scale - r, width: 2 * r, height: 2 * r))
        }

        mutating func fill(_ cg: CGContext, _ color: CGColor) {
            guard !path.isEmpty else { return }
            cg.addPath(path)
            cg.setFillColor(color)
            cg.fillPath()
            path = CGMutablePath()
        }
    }

    /// Evenly spaced stipple, as in the portfolio's stippled planet: random throws, each rejected
    /// if it lands within `spacing / √density` of a placed dot, so density follows tone without
    /// the clumps of plain random sampling. A grid of cell `spacing` (density ≤ 1 keeps at most a
    /// few dots per cell) makes the neighbor check cheap.
    static func stipple(
        _ rand: inout Random,
        bounds: (x0: Double, y0: Double, x1: Double, y1: Double),
        spacing: Double,
        budget: Double,
        density: (Double, Double) -> Double,
        emit: (Double, Double, Double) -> Void
    ) {
        let x0 = max(0, bounds.x0), y0 = max(0, bounds.y0), x1 = min(1, bounds.x1), y1 = min(1, bounds.y1)
        let w = x1 - x0, h = y1 - y0
        guard w > 0, h > 0 else { return }
        let columns = Int((w / spacing).rounded(.up)) + 1, rows = Int((h / spacing).rounded(.up)) + 1
        var head = [Int32](repeating: -1, count: columns * rows)
        var next: [Int32] = [], px: [Double] = [], py: [Double] = []
        let tries = Int(w * h * budget / (spacing * spacing))
        for _ in 0..<tries {
            let x = x0 + rand.next() * w, y = y0 + rand.next() * h
            let d = density(x, y)
            guard d >= 0.004 else { continue }
            let gap = spacing / d.squareRoot(), gap2 = gap * gap, reach = Int((gap / spacing).rounded(.up))
            let cx = min(columns - 1, Int((x - x0) / spacing)), cy = min(rows - 1, Int((y - y0) / spacing))
            var clear = true
            search: for gy in max(0, cy - reach)...min(rows - 1, cy + reach) {
                for gx in max(0, cx - reach)...min(columns - 1, cx + reach) {
                    var j = head[gy * columns + gx]
                    while j >= 0 {
                        let dx = px[Int(j)] - x, dy = py[Int(j)] - y
                        if dx * dx + dy * dy < gap2 { clear = false; break search }
                        j = next[Int(j)]
                    }
                }
            }
            guard clear else { continue }
            let cell = cy * columns + cx
            next.append(head[cell])
            head[cell] = Int32(px.count)
            px.append(x)
            py.append(y)
            emit(x, y, 0.85 + rand.next() * 0.3)
        }
    }
}

// MARK: - View

/// A generated cover, rendered off the main thread at the view's pixel size and cached. Shows the
/// cover's field color until it's ready. Use through `ArtworkView(.generated(seed:))`.
struct GeneratedCover: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale
    let seed: String
    @State private var rendered: (key: String, image: CGImage)?

    var body: some View {
        GeometryReader { proxy in
            let pixels = Self.bucket(proxy.size.width * displayScale)
            let key = "\(seed)@\(pixels)"
            let image = rendered?.key == key ? rendered?.image : CoverArt.cached(seed: seed, pixels: pixels)
            ZStack {
                CoverArt.background(seed: seed)
                if let image {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .interpolation(.high)
                        .transition(.opacity)
                }
            }
            .task(id: key) {
                guard pixels > 0 else { return }
                // Keep a cache hit in state too: the cache can evict it later, and the task won't
                // run again while the key stays the same.
                if let hit = CoverArt.cached(seed: seed, pixels: pixels) {
                    rendered = (key, hit)
                    return
                }
                guard let image = await CoverArt.image(seed: seed, pixels: pixels, scale: displayScale) else { return }
                withAnimation(theme.motion.snappy) { rendered = (key, image) }
            }
        }
    }

    /// Rounds up to 32px so near-identical sizes share one cached render.
    private static func bucket(_ pixels: CGFloat) -> Int {
        Int((pixels / 32).rounded(.up)) * 32
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))]) {
        ForEach(0..<12, id: \.self) { i in
            ArtworkView(.generated(seed: CoverArt.seed(id: "preview-\(i)")))
        }
    }
    .padding()
}
