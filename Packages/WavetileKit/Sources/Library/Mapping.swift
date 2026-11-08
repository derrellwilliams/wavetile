import Foundation
import JellyfinKit
import Persistence

// Database records → UI models shared with API-backed screens.

public extension AlbumRecord {
    var summary: AlbumSummary {
        AlbumSummary(id: id, title: title, artist: artistName, year: year, imageTag: imageTag)
    }
}

public extension TrackRecord {
    var summary: TrackSummary {
        TrackSummary(
            id: id,
            title: title,
            artist: artistName,
            trackNumber: trackNumber,
            discNumber: discNumber,
            duration: durationMs.map { .milliseconds($0) },
            normalizationGain: normalizationGain
        )
    }
}

// Server items → database records. The server's data is untrusted and often incomplete
// (untagged files, empty arrays, nonsense durations), so these never trap and fill gaps with
// the same "Unknown …" names the lists already show.

enum ServerText {
    /// The text, trimmed, or nil when it's missing or blank.
    static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The first real name in the list, or nil.
    static func first(_ names: [String]?) -> String? {
        (names ?? []).lazy.compactMap(nonBlank).first
    }

    /// Artist names joined for display, or nil when the list is missing or has no real name.
    static func names(_ names: [String]?) -> String? {
        let real = (names ?? []).compactMap(nonBlank)
        return real.isEmpty ? nil : real.joined(separator: ", ")
    }
}

enum ServerDuration {
    /// Longest duration kept, a year in milliseconds. Anything beyond it is bad data, and the cap
    /// keeps the sum of a playlist's durations far from overflowing `Int`.
    static let maxMs = 365 * 24 * 60 * 60 * 1000

    /// Jellyfin ticks (100 ns) as milliseconds, clamped to 0...`maxMs`; nil when the server sent none.
    static func milliseconds(ticks: Int?) -> Int? {
        ticks.map { min(max($0 / 10_000, 0), maxMs) }
    }
}
