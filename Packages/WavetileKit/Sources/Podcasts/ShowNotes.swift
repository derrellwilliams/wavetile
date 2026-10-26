import Foundation

/// Turns untrusted show-notes HTML into a styled `AttributedString`.
///
/// Security: nothing is rendered as HTML (no web view, no `NSAttributedString` HTML import,
/// which can fetch remote resources). An allowlist keeps paragraphs, line breaks, lists, bold,
/// italic and links; everything else becomes plain text, and `script`/`style` content is dropped.
/// Links keep only http(s) and mailto URLs. Timestamps like `12:34` become `wavetile-seek:`
/// links the player handles.
public enum ShowNotes {
    public static let seekScheme = "wavetile-seek"

    /// Seconds from a `wavetile-seek://<seconds>` link.
    public static func seekTime(_ url: URL) -> Double? {
        guard url.scheme == seekScheme else { return nil }
        return Double(url.host() ?? "")
    }

    public static func attributed(html: String) -> AttributedString {
        var output = AttributedString()
        var bold = 0, italic = 0
        var link: URL?
        var skipping: String?
        var listDepth = 0
        var pendingBreaks = 0

        func appendText(_ raw: String) {
            let decoded = decodeEntities(raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression))
            guard !decoded.trimmingCharacters(in: .whitespaces).isEmpty || (!output.characters.isEmpty && decoded == " ") else { return }
            var piece = decoded
            if pendingBreaks > 0 {
                if !output.characters.isEmpty { output.append(AttributedString(String(repeating: "\n", count: pendingBreaks))) }
                pendingBreaks = 0
                piece = String(piece.drop(while: { $0 == " " }))
            } else if output.characters.last == "\n" {
                piece = String(piece.drop(while: { $0 == " " }))
            }
            guard !piece.isEmpty else { return }
            var run = link == nil ? linkTimestamps(piece) : AttributedString(piece)
            if let link { run.link = link }
            if bold > 0 && italic > 0 {
                run.inlinePresentationIntent = [.stronglyEmphasized, .emphasized]
            } else if bold > 0 {
                run.inlinePresentationIntent = .stronglyEmphasized
            } else if italic > 0 {
                run.inlinePresentationIntent = .emphasized
            }
            output.append(run)
        }

        func requestBreaks(_ count: Int) {
            pendingBreaks = max(pendingBreaks, count)
        }

        var index = html.startIndex
        while index < html.endIndex {
            guard let open = html[index...].firstIndex(of: "<") else {
                if skipping == nil { appendText(String(html[index...])) }
                break
            }
            if skipping == nil, open > index { appendText(String(html[index ..< open])) }
            guard let close = html[open...].firstIndex(of: ">") else {
                if skipping == nil { appendText(String(html[open...])) }
                break
            }
            let tag = html[html.index(after: open) ..< close]
            index = html.index(after: close)

            let isClosing = tag.hasPrefix("/")
            let name = tag.drop(while: { $0 == "/" })
                .prefix(while: { $0.isLetter || $0.isNumber })
                .lowercased()

            if let skipped = skipping {
                if isClosing, name == skipped { skipping = nil }
                continue
            }
            switch name {
            case "script", "style", "iframe", "object", "noscript":
                if !isClosing { skipping = name }
            case "br":
                pendingBreaks += 1
            case "p", "div", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6":
                requestBreaks(2)
                if name.hasPrefix("h") {
                    bold += isClosing ? -1 : 1
                    bold = max(bold, 0)
                }
            case "ul", "ol":
                listDepth = max(0, listDepth + (isClosing ? -1 : 1))
                requestBreaks(listDepth == 0 && isClosing ? 2 : 1)
            case "li":
                if !isClosing {
                    requestBreaks(1)
                    appendText("• ")
                }
            case "b", "strong":
                bold = max(0, bold + (isClosing ? -1 : 1))
            case "i", "em":
                italic = max(0, italic + (isClosing ? -1 : 1))
            case "a":
                link = isClosing ? nil : href(in: String(tag))
            default:
                break
            }
        }
        return output
    }

    /// Plain-text timestamps (`1:02:03`, `12:34`) become seek links.
    static func linkTimestamps(_ text: String) -> AttributedString {
        var result = AttributedString()
        let pattern = /\b(?:(\d{1,2}):)?([0-5]?\d):([0-5]\d)\b/
        var cursor = text.startIndex
        for match in text.matches(of: pattern) {
            result.append(AttributedString(String(text[cursor ..< match.range.lowerBound])))
            let hours = match.output.1.flatMap { Double($0) } ?? 0
            let seconds = hours * 3600 + (Double(match.output.2) ?? 0) * 60 + (Double(match.output.3) ?? 0)
            var stamp = AttributedString(String(text[match.range]))
            stamp.link = URL(string: "\(seekScheme)://\(Int(seconds))")
            result.append(stamp)
            cursor = match.range.upperBound
        }
        result.append(AttributedString(String(text[cursor...])))
        return result
    }

    /// The `href` of an anchor tag, if it's a safe link.
    static func href(in tag: String) -> URL? {
        guard let match = tag.firstMatch(of: /(?i)href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/) else { return nil }
        let raw = decodeEntities(String(match.output.1 ?? match.output.2 ?? match.output.3 ?? ""))
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme)
        else { return nil }
        return url
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“",
        "copy": "©", "reg": "®", "trade": "™", "bull": "•", "middot": "·",
    ]

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let entity = text[text.index(after: index) ..< semicolon]
            var replacement: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X"), let code = UInt32(entity.dropFirst(2), radix: 16) {
                replacement = Unicode.Scalar(code).map { String(Character($0)) }
            } else if entity.hasPrefix("#"), let code = UInt32(entity.dropFirst()) {
                replacement = Unicode.Scalar(code).map { String(Character($0)) }
            } else {
                replacement = namedEntities[entity.lowercased()]
            }
            if let replacement {
                result += replacement
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }
}
