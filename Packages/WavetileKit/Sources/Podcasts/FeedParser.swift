import Foundation

public struct ParsedFeed: Sendable, Equatable {
    public var title: String
    public var author: String
    public var summary: String
    public var artworkURL: URL?
    public var websiteURL: URL?
    public var isSerial: Bool
    public var episodes: [ParsedEpisode]
    public var people: [PodcastPerson] = []
}

public struct ParsedEpisode: Sendable, Equatable {
    public var guid: String
    public var title: String
    public var summary: String
    public var notesHTML: String
    public var publishedAt: Date?
    public var duration: Double?
    public var audioURL: URL
    public var mimeType: String?
    public var byteLength: Int64?
    public var artworkURL: URL?
    public var season: Int?
    public var number: Int?
    public var episodeType: String?
    public var chaptersURL: URL?
    public var transcriptURL: URL?
    public var transcriptType: String?
    public var people: [PodcastPerson] = []
}

/// HTTP validators for conditional refreshes.
public struct FeedValidators: Sendable, Equatable {
    public var etag: String?
    public var lastModified: String?
    /// SHA-256 of the last body, for hosts that send neither header (they answer 200 every time).
    public var bodyHash: String?

    public init(etag: String?, lastModified: String?, bodyHash: String? = nil) {
        self.etag = etag
        self.lastModified = lastModified
        self.bodyHash = bodyHash
    }
}

public enum FeedError: LocalizedError, Equatable {
    case notAFeed
    case tooLarge
    case insecure
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .notAFeed: "That link isn't a podcast feed."
        case .tooLarge: "This feed is too large to load."
        case .insecure: "This feed isn't available over a secure connection."
        case let .http(code): "The podcast's server returned an error (\(code))."
        }
    }
}

/// Parses podcast RSS 2.0 with the `itunes:` and Podcasting 2.0 (`podcast:`) tags.
///
/// Security: feed XML is untrusted. External entities are never resolved, callers cap the size
/// (`FeedFetcher.maxBytes`), text fields are length-limited, and only http(s) URLs are kept.
public enum FeedParser {
    static let maxEpisodes = 3000
    static let maxNotesLength = 100_000

    public static func parse(_ data: Data) throws -> ParsedFeed {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        // Real-world feeds are often slightly malformed at the end; keep what parsed before the error.
        _ = parser.parse()
        guard delegate.sawChannel else { throw FeedError.notAFeed }
        return delegate.feed()
    }

    // MARK: - Field helpers (internal for tests)

    /// `3723`, `3723.5`, `62:03` or `1:02:03` → seconds.
    static func duration(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let value = parts.compactMap(\.self).reduce(0) { $0 * 60 + $1 }
        return value > 0 ? value : nil
    }

    private static let dateFormats = [
        "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm Z", "dd MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd",
    ]

    /// Built once: making a formatter (and switching its format) per episode cost about half a
    /// second on a 3000-episode feed. DateFormatter is thread-safe for parsing (iOS 7+), and these
    /// are never mutated after creation, so sharing them across feeds parsed in parallel is safe.
    nonisolated(unsafe) private static let dateFormatters: [DateFormatter] = dateFormats.map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    static func date(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// Only web URLs: never `file:`, `javascript:` or app schemes from a feed.
    static func webURL(_ text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let url = URL(string: text) ?? URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? ""),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host() != nil
        else { return nil }
        return url
    }

    /// Show notes HTML → a short plain-text summary for rows.
    static func plainText(_ html: String, limit: Int = 400) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = ShowNotes.decodeEntities(text)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ([.,;:!?])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// HTML to plain text that keeps paragraph breaks (blank lines), for transcripts.
    static func plainParagraphs(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<(/p|br\\s*/?|/div|/h[1-6])>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return ShowNotes.decodeEntities(text)
    }

    /// Feeds can list a whole crew; more than this isn't useful on a phone.
    static let maxPeople = 12

    static func person(name: String, attributes: [String: String]) -> PodcastPerson? {
        let name = ShowNotes.decodeEntities(name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return PodcastPerson(
            name: String(name.prefix(80)),
            role: (attributes["role"] ?? "host").lowercased(),
            imageURL: webURL(attributes["img"]),
            href: webURL(attributes["href"])
        )
    }

    /// Timed formats first (they can seek), then the plainer ones.
    static func preferredTranscript(_ transcripts: [(url: URL, type: String)]) -> (url: URL, type: String)? {
        let order = ["text/vtt", "application/x-subrip", "application/srt", "application/json", "text/html", "text/plain"]
        return transcripts
            .filter { order.contains($0.type) }
            .min { order.firstIndex(of: $0.type)! < order.firstIndex(of: $1.type)! }
    }

    // MARK: - Delegate

    private final class Delegate: NSObject, XMLParserDelegate {
        var sawChannel = false
        private var path: [String] = []
        private var text = ""

        private var title = ""
        private var author = ""
        private var channelSummary = ""
        private var channelDescription = ""
        private var artwork: URL?
        private var imageURL: URL?
        private var website: URL?
        private var type = ""
        private var episodes: [ParsedEpisode] = []
        private var channelPeople: [PodcastPerson] = []
        /// A `podcast:person`'s attributes, held until its closing tag brings the name.
        private var personAttributes: [String: String]?

        private var item: ItemFields?

        struct ItemFields {
            var guid = ""
            var title = ""
            var description = ""
            var content = ""
            var itunesSummary = ""
            var pubDate = ""
            var duration = ""
            var enclosureURL: URL?
            var enclosureType: String?
            var enclosureLength: Int64?
            var image: URL?
            var season = ""
            var number = ""
            var episodeType = ""
            var chapters: URL?
            var transcripts: [(url: URL, type: String)] = []
            var people: [PodcastPerson] = []
        }

        func feed() -> ParsedFeed {
            let summary = channelSummary.isEmpty ? channelDescription : channelSummary
            return ParsedFeed(
                title: title.isEmpty ? "Untitled Podcast" : title,
                author: author,
                summary: FeedParser.plainText(summary, limit: 4000),
                artworkURL: artwork ?? imageURL,
                websiteURL: website,
                isSerial: type.lowercased() == "serial",
                episodes: episodes,
                people: channelPeople
            )
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            let element = name.lowercased()
            path.append(element)
            text = ""
            switch element {
            case "channel":
                sawChannel = true
            case "item":
                item = episodes.count < FeedParser.maxEpisodes ? ItemFields() : nil
            case "enclosure":
                guard item != nil, item?.enclosureURL == nil else { break }
                item?.enclosureURL = FeedParser.webURL(attributes["url"])
                item?.enclosureType = attributes["type"]
                item?.enclosureLength = attributes["length"].flatMap { Int64($0) }
            case "itunes:image":
                let href = FeedParser.webURL(attributes["href"])
                if item != nil { item?.image = href } else if artwork == nil { artwork = href }
            case "podcast:chapters":
                item?.chapters = FeedParser.webURL(attributes["url"])
            case "podcast:transcript":
                if let url = FeedParser.webURL(attributes["url"]) {
                    item?.transcripts.append((url, (attributes["type"] ?? "").lowercased()))
                }
            case "podcast:person":
                personAttributes = attributes
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            // Cap any single field so a hostile feed can't balloon memory.
            guard text.utf8.count < FeedParser.maxNotesLength else { return }
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard text.utf8.count < FeedParser.maxNotesLength else { return }
            text += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let element = name.lowercased()
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = path.dropLast().last
            defer {
                path.removeLast()
                text = ""
            }

            if element == "podcast:person", let attributes = personAttributes {
                personAttributes = nil
                if let person = FeedParser.person(name: value, attributes: attributes) {
                    if item != nil, path.contains("item") {
                        if item!.people.count < FeedParser.maxPeople { item?.people.append(person) }
                    } else if parent == "channel", channelPeople.count < FeedParser.maxPeople {
                        channelPeople.append(person)
                    }
                }
                return
            }

            if item != nil, path.contains("item") {
                switch element {
                case "guid": item?.guid = value
                case "title" where parent == "item": item?.title = value
                case "description": item?.description = text
                case "content:encoded": item?.content = text
                case "itunes:summary": item?.itunesSummary = text
                case "pubdate": item?.pubDate = value
                case "itunes:duration": item?.duration = value
                case "itunes:season": item?.season = value
                case "itunes:episode": item?.number = value
                case "itunes:episodetype": item?.episodeType = value
                case "item": finishItem()
                default: break
                }
                return
            }
            if element == "item" { item = nil; return }

            guard parent == "channel" || parent == "image" else { return }
            switch (parent, element) {
            case ("channel", "title"): title = value
            case ("channel", "itunes:author"): author = value
            case ("channel", "itunes:summary"): channelSummary = text
            case ("channel", "description"): channelDescription = text
            case ("channel", "link"): website = FeedParser.webURL(value)
            case ("channel", "itunes:type"): type = value
            case ("image", "url"): imageURL = FeedParser.webURL(value)
            default: break
            }
        }

        private func finishItem() {
            defer { item = nil }
            guard let fields = item, let audio = fields.enclosureURL else { return }
            let notes = [fields.content, fields.description, fields.itunesSummary].first { !$0.isEmpty } ?? ""
            let summarySource = [fields.itunesSummary, fields.description, fields.content].first { !$0.isEmpty } ?? ""
            let transcript = FeedParser.preferredTranscript(fields.transcripts)
            episodes.append(ParsedEpisode(
                guid: fields.guid.isEmpty ? audio.absoluteString : fields.guid,
                title: fields.title.isEmpty ? "Untitled Episode" : fields.title,
                summary: FeedParser.plainText(summarySource),
                notesHTML: String(notes.prefix(FeedParser.maxNotesLength)),
                publishedAt: FeedParser.date(fields.pubDate),
                duration: FeedParser.duration(fields.duration),
                audioURL: audio,
                mimeType: fields.enclosureType,
                byteLength: fields.enclosureLength,
                artworkURL: fields.image,
                season: Int(fields.season),
                number: Int(fields.number),
                episodeType: fields.episodeType.isEmpty ? nil : fields.episodeType.lowercased(),
                chaptersURL: fields.chapters,
                transcriptURL: transcript?.url,
                transcriptType: transcript?.type,
                people: fields.people
            ))
        }
    }
}
