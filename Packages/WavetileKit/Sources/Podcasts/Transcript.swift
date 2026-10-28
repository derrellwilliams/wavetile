import Foundation

/// A paragraph of an episode transcript. `start` is set for timed formats, so tapping it can seek.
public struct TranscriptParagraph: Hashable, Sendable, Identifiable {
    public var id: Int
    public var start: Double?
    public var speaker: String?
    public var text: String
}

/// Podcasting 2.0 transcripts (`podcast:transcript`): WebVTT, SRT, JSON, HTML or plain text,
/// turned into readable paragraphs. Fetched on demand when an episode page opens.
public enum Transcript {
    /// Larger than any real transcript; a guard against hostile hosts.
    static let maxBytes = 5_000_000

    public static func load(url: URL, type: String?) async throws -> [TranscriptParagraph] {
        guard let secure = PodcastNetwork.secure(url) else { throw FeedError.insecure }
        let (data, response) = try await PodcastNetwork.session.data(from: secure)
        try PodcastNetwork.check(response)
        guard data.count <= maxBytes else { throw FeedError.tooLarge }
        return parse(String(decoding: data, as: UTF8.self), type: type ?? "")
    }

    static func parse(_ text: String, type: String) -> [TranscriptParagraph] {
        let cues: [Cue] = switch type {
        case "text/vtt", "application/x-subrip", "application/srt": timedCues(text)
        case "application/json": jsonCues(text)
        case "text/html": blocks(FeedParser.plainParagraphs(text))
        default: blocks(text)
        }
        return paragraphs(from: cues)
    }

    struct Cue {
        var start: Double?
        var speaker: String?
        var text: String
    }

    /// WebVTT and SRT share a shape: blocks with a `start --> end` line, then the words.
    /// VTT names speakers inline as `<v Name>`.
    static func timedCues(_ text: String) -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let start = lines[timing].components(separatedBy: "-->").first.flatMap { timestamp($0) }
            var words = lines[(timing + 1)...].joined(separator: " ")
            var speaker: String?
            if let match = words.firstMatch(of: /<v\s+([^>]+)>/) {
                speaker = String(match.1).trimmingCharacters(in: .whitespaces)
            }
            words = words.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            words = ShowNotes.decodeEntities(words).trimmingCharacters(in: .whitespaces)
            return words.isEmpty ? nil : Cue(start: start, speaker: speaker, text: words)
        }
    }

    /// `{"segments": [{"speaker", "startTime", "body"}]}`.
    static func jsonCues(_ text: String) -> [Cue] {
        struct File: Decodable {
            var segments: [Segment]
            struct Segment: Decodable {
                var speaker: String?
                var startTime: Double?
                var body: String
            }
        }
        guard let file = try? JSONDecoder().decode(File.self, from: Data(text.utf8)) else { return [] }
        return file.segments.map { Cue(start: $0.startTime, speaker: $0.speaker, text: $0.body.trimmingCharacters(in: .whitespaces)) }
    }

    /// Untimed text: one cue per blank-line-separated block.
    static func blocks(_ text: String) -> [Cue] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Cue(text: $0) }
    }

    /// Timed cues are a line or a few words each; they're joined into paragraphs that break on
    /// a new speaker, or after a sentence once a paragraph is long enough to read as one.
    static func paragraphs(from cues: [Cue]) -> [TranscriptParagraph] {
        var result: [TranscriptParagraph] = []
        var current: Cue?
        for cue in cues {
            if var open = current {
                let newSpeaker = cue.speaker != nil && cue.speaker != open.speaker
                let ended = open.text.count > 320 && open.text.last.map { ".?!".contains($0) } == true
                if !newSpeaker, !ended {
                    open.text += " " + cue.text
                    current = open
                    continue
                }
                result.append(TranscriptParagraph(id: result.count, start: open.start, speaker: open.speaker, text: open.text))
            }
            current = cue
        }
        if let open = current {
            result.append(TranscriptParagraph(id: result.count, start: open.start, speaker: open.speaker, text: open.text))
        }
        return result
    }

    /// `01:02:03.456`, `02:03,456` or `02:03` → seconds.
    static func timestamp(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ":")
            .compactMap { Double($0) }
        guard (2 ... 3).contains(parts.count) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
