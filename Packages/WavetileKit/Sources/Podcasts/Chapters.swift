import AVFoundation
import Foundation

public struct Chapter: Hashable, Sendable, Identifiable {
    public var start: Double
    public var title: String
    public var id: Double { start }

    public init(start: Double, title: String) {
        self.start = start
        self.title = title
    }
}

/// Loads episode chapters, best source first: Podcasting 2.0 JSON chapters when the feed links
/// them, then chapters embedded in the audio file (ID3 / MP4), then a timestamp list in the
/// show notes ("00:00 Intro", "(12:34) Topic").
public enum ChapterLoader {
    @concurrent public static func load(chaptersURL: URL?, audioURL: URL, notesHTML: String = "", duration: Double? = nil) async -> [Chapter] {
        if let chaptersURL, let chapters = try? await json(chaptersURL), !chapters.isEmpty { return chapters }
        let embedded = await embedded(audioURL)
        if !embedded.isEmpty { return embedded }
        return ShowNotes.chapters(html: notesHTML, duration: duration)
    }

    static func json(_ url: URL) async throws -> [Chapter] {
        guard let secure = PodcastNetwork.secure(url) else { return [] }
        // The URL comes from the feed (untrusted), so the body is capped while it streams in.
        let (bytes, response) = try await PodcastNetwork.session.bytes(from: secure)
        try PodcastNetwork.check(response)
        return try parseJSON(try await PodcastNetwork.read(bytes, response, maxBytes: 2 * 1024 * 1024))
    }

    static func parseJSON(_ data: Data) throws -> [Chapter] {
        struct File: Decodable {
            var chapters: [Entry]
            struct Entry: Decodable {
                var startTime: Double
                var title: String?
                var toc: Bool?
            }
        }
        return try JSONDecoder().decode(File.self, from: data).chapters
            .filter { $0.toc != false }
            .map { Chapter(start: max($0.startTime, 0), title: $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") }
            .sorted { $0.start < $1.start }
    }

    /// Embedded chapters. Streams only the file's header for remote audio; no Jellyfin headers.
    static func embedded(_ url: URL) async -> [Chapter] {
        let asset = AVURLAsset(url: url)
        guard let groups = try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages) else { return [] }
        var chapters: [Chapter] = []
        for group in groups {
            let title = (try? await AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first?.load(.stringValue)) ?? nil
            chapters.append(Chapter(start: group.timeRange.start.seconds, title: title ?? "Chapter \(chapters.count + 1)"))
        }
        return chapters
    }
}
