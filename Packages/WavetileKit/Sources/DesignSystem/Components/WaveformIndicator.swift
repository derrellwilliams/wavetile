import SwiftUI

/// The now-playing marker in track rows: the logo's wave (`WaveMark`), small, with its ripple
/// running through the lobes while audio plays and the resting line when paused. A deeper swell
/// than the logo's, so the motion reads at this size; off with Reduce Motion.
public struct WaveformIndicator: View {
    private let isAnimating: Bool
    private let size: CGFloat

    public init(isAnimating: Bool, size: CGFloat = 22) {
        self.isAnimating = isAnimating
        self.size = size
    }

    public var body: some View {
        WaveMark(isAnimating: isAnimating, width: size, strength: 0.7, lineWidth: 1.75)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
