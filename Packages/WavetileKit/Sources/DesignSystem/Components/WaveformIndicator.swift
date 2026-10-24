import SwiftUI

/// The Phosphor `waveform` glyph, drawn live so its bars can move while audio plays.
///
/// At rest it matches `Glyph.waveform.image`, except the tallest bar is a little shorter. While animating, each bar breathes
/// around its resting height at its own rate; pausing springs the bars back to rest from wherever
/// they are, so there's no snap. Off with Reduce Motion.
public struct WaveformIndicator: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let isAnimating: Bool
    private let size: CGFloat

    public init(isAnimating: Bool, size: CGFloat = 24) {
        self.isAnimating = isAnimating
        self.size = size
    }

    private var active: Bool { isAnimating && !reduceMotion }

    public var body: some View {
        TimelineView(.animation(paused: !active)) { context in
            WaveformShape(
                time: context.date.timeIntervalSinceReferenceDate,
                amplitude: active ? 1 : 0
            )
        }
        .animation(theme.motion.smooth, value: active)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Five capsules on Phosphor's 256-unit grid, matching `waveform.svg` (bold weight).
nonisolated struct WaveformShape: Shape {
    var time: Double
    var amplitude: Double

    var animatableData: Double {
        get { amplitude }
        set { amplitude = newValue }
    }

    /// Center x and resting length of each bar, from the SVG path (caps included). The tall
    /// second bar is shortened from 216 so it stays inside the frame at full stretch.
    private static let bars: [(x: CGFloat, length: CGFloat)] = [
        (48, 88), (88, 176), (128, 152), (168, 88), (208, 120),
    ]
    private static let barWidth: CGFloat = 24
    /// Bars move at unrelated rates so the pattern never visibly repeats.
    private static let rates: [Double] = [2.3, 3.1, 2.7, 3.7, 2.9]

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 256
        let origin = CGPoint(x: rect.midX - 128 * scale, y: rect.midY - 128 * scale)
        var path = Path()
        for (index, bar) in Self.bars.enumerated() {
            let rate = Self.rates[index]
            // Two summed sines read as organic motion; result spans roughly 0...1.
            let wave = (sin(time * rate + Double(index)) + sin(time * rate * 1.618) * 0.5 + 1.5) / 3
            // Shrink and grow around the resting length, never collapsing past a round dot.
            let factor = 1 + amplitude * (wave * 0.9 - 0.45)
            let length = max(Self.barWidth, bar.length * factor)
            let barRect = CGRect(
                x: origin.x + (bar.x - Self.barWidth / 2) * scale,
                y: origin.y + (128 - length / 2) * scale,
                width: Self.barWidth * scale,
                height: length * scale
            )
            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: Self.barWidth / 2 * scale, height: Self.barWidth / 2 * scale))
        }
        return path
    }
}

public extension EnvironmentValues {
    /// Whether audio is currently playing (not just loaded). Set once at the app root so
    /// design-system views like `TrackRow` can animate without depending on the player.
    @Entry var isAudioPlaying = false
}

#Preview {
    @Previewable @State var playing = true
    VStack(spacing: 24) {
        HStack(spacing: 24) {
            WaveformIndicator(isAnimating: playing)
            Glyph.waveform.image
        }
        .foregroundStyle(.white)
        Button(playing ? "Pause" : "Play") { playing.toggle() }
    }
    .padding()
    .background(Color(white: 0.1))
}
