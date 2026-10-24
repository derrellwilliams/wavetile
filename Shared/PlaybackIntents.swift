// Compiled into both the app and the widget extension (App Intents must be defined in each
// binary that references them). `AudioPlaybackIntent` makes iOS run perform() in the app.
import AppIntents
import WidgetShared

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses Wavetile.")

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackCommandCenter.shared.perform(.togglePlayPause)
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Skips to the next song in Wavetile.")

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackCommandCenter.shared.perform(.next)
        return .result()
    }
}
