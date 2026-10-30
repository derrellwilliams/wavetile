import Foundation

/// A resolved audio stream. Auth travels in `headers` (not the URL) so the token never lands
/// in server/proxy access logs or crash reports that capture URLs.
public struct StreamRequest: Sendable {
    public let url: URL
    public let headers: [String: String]
    public let playSessionID: String
}

public extension LibraryClient {
    /// Formats AVFoundation decodes natively. Jellyfin direct-plays these and transcodes the rest.
    static let directPlayContainers = ["mp3", "aac", "m4a|aac", "m4a|alac", "m4b|aac", "flac", "alac", "wav", "aiff"]

    /// Universal audio endpoint: the server picks direct play when the file is in
    /// `directPlayContainers` and under `maxBitrate`, otherwise transcodes to 320k MP3.
    func streamRequest(trackID: String, maxBitrate: Int = 140_000_000) -> StreamRequest? {
        let playSessionID = UUID().uuidString
        let params = Paths.GetUniversalAudioStreamParameters(
            container: Self.directPlayContainers,
            deviceID: identity.deviceID,
            userID: session.userID,
            audioCodec: "mp3",
            maxStreamingBitrate: maxBitrate,
            audioBitRate: 320_000,
            transcodingContainer: "mp3",
            transcodingProtocol: .http,
            // No redirects: for items with a remote path Jellyfin would answer 302 to another host,
            // and AVFoundation may carry the Authorization header (the token) along with it.
            // Without redirection the server streams the item itself.
            enableRedirection: false
        )
        guard var url = client.url(with: Paths.getUniversalAudioStream(itemID: trackID, parameters: params)) else { return nil }
        url.append(queryItems: [URLQueryItem(name: "PlaySessionId", value: playSessionID)])
        return StreamRequest(url: url, headers: ["Authorization": authorizationHeader], playSessionID: playSessionID)
    }

    /// `Authorization: MediaBrowser ...` header with this session's token.
    var authorizationHeader: String {
        func quote(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: ""))\"" }
        return "MediaBrowser Client=\(quote(identity.clientName)), Device=\(quote(identity.deviceName)), "
            + "DeviceId=\(quote(identity.deviceID)), Version=\(quote(identity.version)), Token=\(quote(token))"
    }

    // MARK: Session reporting (drives play counts, Recently Played, and the server dashboard)

    func reportStart(trackID: String, playSessionID: String, positionSeconds: Double, isPaused: Bool) async {
        let info = PlaybackStateInfo(
            canSeek: true,
            isPaused: isPaused,
            itemID: trackID,
            playMethod: .directPlay,
            playSessionID: playSessionID,
            positionTicks: Self.ticks(positionSeconds)
        )
        try? await client.send(Paths.reportPlaybackStart(info))
    }

    func reportProgress(trackID: String, playSessionID: String, positionSeconds: Double, isPaused: Bool) async {
        let info = PlaybackStateInfo(
            canSeek: true,
            isPaused: isPaused,
            itemID: trackID,
            playMethod: .directPlay,
            playSessionID: playSessionID,
            positionTicks: Self.ticks(positionSeconds)
        )
        try? await client.send(Paths.reportPlaybackProgress(info))
    }

    /// Returns false when the report didn't reach the server (offline), so the play can be
    /// recorded later with `markPlayed`.
    @discardableResult
    func reportStopped(trackID: String, playSessionID: String, positionSeconds: Double) async -> Bool {
        let info = PlaybackStopInfo(itemID: trackID, playSessionID: playSessionID, positionTicks: Self.ticks(positionSeconds))
        do {
            try await client.send(Paths.reportPlaybackStopped(info))
            return true
        } catch {
            return false
        }
    }

    /// Records a play that happened earlier (offline), at the time it happened. Jellyfin bumps the
    /// play count and last-played date, which drive Recently Played and Most Played.
    func markPlayed(trackID: String, at date: Date) async -> Bool {
        (try? await client.send(Paths.markPlayedItem(itemID: trackID, userID: session.userID, datePlayed: date))) != nil
    }

    private static func ticks(_ seconds: Double) -> Int {
        Int((seconds.isFinite ? max(0, seconds) : 0) * 10_000_000)
    }
}
