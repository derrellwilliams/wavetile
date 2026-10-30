import Foundation

/// What's mirrored to the user's Jellyfin DisplayPreferences (`CustomPrefs`), so podcasts follow
/// the account to other devices without a separate backend.
///
/// Privacy: server admins (and any client signed in as the user) can read these preferences.
/// Only feed URLs, opaque episode IDs and timestamps are stored: no titles, no history list.
/// Private feeds (see `isPrivate`) are never synced.
public struct PodcastSyncState: Equatable, Sendable {
    public var enabled: Bool?
    public var enabledUpdated: Date?
    public var subscriptions: [URL]
    public var subscriptionsUpdated: Date?
    /// episodeID → (position, updated)
    public var positions: [String: Position]
    /// episodeID → played date
    public var played: [String: Date]

    public struct Position: Equatable, Sendable {
        public var seconds: Double
        public var updated: Date

        public init(seconds: Double, updated: Date) {
            self.seconds = seconds
            self.updated = updated
        }
    }

    public static let preferencesID = "wavetile-podcasts"
    static let maxPositions = 200
    static let maxPlayed = 2000
    static let playedWindow: TimeInterval = 90 * 24 * 3600

    public init(enabled: Bool? = nil, enabledUpdated: Date? = nil, subscriptions: [URL] = [], subscriptionsUpdated: Date? = nil,
                positions: [String: Position] = [:], played: [String: Date] = [:]) {
        self.enabled = enabled
        self.enabledUpdated = enabledUpdated
        self.subscriptions = subscriptions
        self.subscriptionsUpdated = subscriptionsUpdated
        self.positions = positions
        self.played = played
    }

    /// Feeds that look personal stay on device: a token in the query, embedded credentials, a
    /// members-only host or `/private/` path (Supercast, Patreon, Substack), or a token-like path
    /// segment. Errs toward private: a public feed misjudged here only skips syncing.
    public static func isPrivate(_ url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !(components?.queryItems ?? []).isEmpty || components?.user != nil || components?.password != nil { return true }
        let host = url.host()?.lowercased() ?? ""
        if privateHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        return url.pathComponents.contains { segment in
            segment.lowercased() == "private" || looksLikeToken(segment)
        }
    }

    static let privateHosts = ["supercast.com", "patreon.com", "memberful.com", "supportingcast.fm", "glow.fm"]

    /// 20+ characters of letters and digits mixed (with `-` or `_`), like an access key. UUIDs
    /// are left out: hosts such as Omny put public show IDs in the path that way.
    static func looksLikeToken(_ segment: String) -> Bool {
        let name = segment.split(separator: ".").first.map(String.init) ?? segment
        guard name.count >= 20, name.wholeMatch(of: /[A-Za-z0-9_-]+/) != nil,
              name.contains(where: \.isLetter), name.contains(where: \.isNumber) else { return false }
        return name.wholeMatch(of: /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/) == nil
    }

    // MARK: CustomPrefs encoding

    public init(customPrefs prefs: [String: String]) {
        func date(_ key: String) -> Date? { prefs[key].flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) }
        enabled = prefs["enabled"].map { $0 == "1" }
        enabledUpdated = date("enabledUpdated")
        subscriptions = (prefs["subs"].flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? [])
            .compactMap(FeedParser.webURL)
        subscriptionsUpdated = date("subsUpdated")
        let rawPositions = prefs["pos"].flatMap { try? JSONDecoder().decode([String: [Double]].self, from: Data($0.utf8)) } ?? [:]
        positions = rawPositions.compactMapValues { pair in
            pair.count == 2 ? Position(seconds: pair[0], updated: Date(timeIntervalSince1970: pair[1])) : nil
        }
        let rawPlayed = prefs["played"].flatMap { try? JSONDecoder().decode([String: Double].self, from: Data($0.utf8)) } ?? [:]
        played = rawPlayed.mapValues(Date.init(timeIntervalSince1970:))
    }

    public var customPrefs: [String: String] {
        func json(_ value: some Encodable) -> String { (try? String(decoding: JSONEncoder().encode(value), as: UTF8.self)) ?? "" }
        func epoch(_ date: Date) -> String { String(Int(date.timeIntervalSince1970)) }
        var prefs: [String: String] = [:]
        if let enabled { prefs["enabled"] = enabled ? "1" : "0" }
        if let enabledUpdated { prefs["enabledUpdated"] = epoch(enabledUpdated) }
        prefs["subs"] = json(subscriptions.filter { !Self.isPrivate($0) }.map(\.absoluteString))
        if let subscriptionsUpdated { prefs["subsUpdated"] = epoch(subscriptionsUpdated) }
        let recentPositions = positions.sorted { $0.value.updated > $1.value.updated }.prefix(Self.maxPositions)
        prefs["pos"] = json(Dictionary(uniqueKeysWithValues: recentPositions.map {
            ($0.key, [($0.value.seconds * 10).rounded() / 10, $0.value.updated.timeIntervalSince1970.rounded()])
        }))
        let cutoff = Date().addingTimeInterval(-Self.playedWindow)
        let recentPlayed = played.filter { $0.value > cutoff }.sorted { $0.value > $1.value }.prefix(Self.maxPlayed)
        prefs["played"] = json(Dictionary(uniqueKeysWithValues: recentPlayed.map { ($0.key, $0.value.timeIntervalSince1970.rounded()) }))
        return prefs
    }

    // MARK: Merging

    /// Combines this device's state with the server's. Per-key last-write-wins: the newer
    /// subscription list and enabled flag win; positions merge per episode by timestamp; played
    /// dates union (a finish anywhere counts).
    public func merged(withRemote remote: PodcastSyncState) -> PodcastSyncState {
        var result = self
        if (remote.subscriptionsUpdated ?? .distantPast) > (subscriptionsUpdated ?? .distantPast) {
            result.subscriptions = remote.subscriptions + subscriptions.filter(Self.isPrivate)
            result.subscriptionsUpdated = remote.subscriptionsUpdated
        }
        if (remote.enabledUpdated ?? .distantPast) > (enabledUpdated ?? .distantPast) {
            result.enabled = remote.enabled
            result.enabledUpdated = remote.enabledUpdated
        }
        for (id, position) in remote.positions where (result.positions[id]?.updated ?? .distantPast) < position.updated {
            result.positions[id] = position
        }
        for (id, date) in remote.played {
            result.played[id] = min(result.played[id] ?? date, date)
        }
        // A finish newer than a stored position supersedes it.
        for (id, date) in result.played where (result.positions[id]?.updated ?? .distantFuture) <= date {
            result.positions[id] = nil
        }
        return result
    }
}
