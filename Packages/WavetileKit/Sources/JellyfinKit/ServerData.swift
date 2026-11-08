import Foundation

// Server items → app records. The server's data is untrusted and often incomplete
// (untagged files, empty arrays, nonsense durations), so these never trap and fill gaps with
// the same "Unknown …" names the lists already show.

package enum ServerText {
    /// The text, trimmed, or nil when it's missing or blank.
    package static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The first real name in the list, or nil.
    package static func first(_ names: [String]?) -> String? {
        (names ?? []).lazy.compactMap(nonBlank).first
    }

    /// Artist names joined for display, or nil when the list is missing or has no real name.
    package static func names(_ names: [String]?) -> String? {
        let real = (names ?? []).compactMap(nonBlank)
        return real.isEmpty ? nil : real.joined(separator: ", ")
    }
}

package enum ServerDuration {
    /// Longest duration kept, a year in milliseconds. Anything beyond it is bad data, and the cap
    /// keeps the sum of a playlist's durations far from overflowing `Int`.
    package static let maxMs = 365 * 24 * 60 * 60 * 1000

    /// Jellyfin ticks (100 ns) as milliseconds, clamped to 0...`maxMs`; nil when the server sent none.
    package static func milliseconds(ticks: Int?) -> Int? {
        ticks.map { min(max($0 / 10_000, 0), maxMs) }
    }
}
