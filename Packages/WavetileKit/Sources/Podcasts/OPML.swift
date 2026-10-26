import Foundation

/// Imports and exports subscription lists in OPML, the format every podcast app shares.
public enum OPML {
    public struct Entry: Hashable, Sendable {
        public var title: String
        public var feedURL: URL
    }

    /// Feed URLs from an OPML file (any nesting; entities never resolved).
    public static func parse(_ data: Data) -> [Entry] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        _ = parser.parse()
        var seen = Set<String>()
        return delegate.entries.filter { seen.insert(PodcastID.show(feedURL: $0.feedURL)).inserted }
    }

    public static func export(_ shows: [ShowRecord]) -> String {
        let outlines = shows.map { show in
            "    <outline type=\"rss\" text=\"\(escape(show.title))\" title=\"\(escape(show.title))\" xmlUrl=\"\(escape(show.feedURL.absoluteString))\"\(show.websiteURL.map { " htmlUrl=\"\(escape($0.absoluteString))\"" } ?? "")/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Wavetile Podcasts</title></head>
          <body>
        \(outlines.joined(separator: "\n"))
          </body>
        </opml>

        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var entries: [Entry] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            guard name.lowercased() == "outline", entries.count < 2000 else { return }
            let lowered = Dictionary(attributes.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
            guard let raw = lowered["xmlurl"], let url = FeedParser.webURL(raw) else { return }
            entries.append(Entry(title: lowered["title"] ?? lowered["text"] ?? url.host() ?? "Podcast", feedURL: url))
        }
    }
}
