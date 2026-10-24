import Foundation

/// Bridge from App Intents (widget buttons) to the app's audio player.
///
/// The intents conform to `AudioPlaybackIntent`, so iOS runs them in the app's process; the app
/// registers a handler at launch and the intent forwards the command to it.
@MainActor
public final class PlaybackCommandCenter {
    public enum Command: Sendable {
        case togglePlayPause, next
    }

    public static let shared = PlaybackCommandCenter()
    public var handler: ((Command) -> Void)?

    public func perform(_ command: Command) {
        handler?(command)
    }
}
