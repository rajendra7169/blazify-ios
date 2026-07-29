import Foundation

/// Apple-style TTML → LRC, ported from the Android module's TTMLParser.
///
/// BetterLyrics serves word-level TTML (`<span begin= end=>` per syllable). We
/// keep each `<p>`'s start time, its full text AND its per-word stamps — the
/// word-by-word animations and the Blazify renderer are built on those. The
/// background / translation / romanisation spans stay excluded; they're separate
/// display tracks, not part of the line.
enum TTML {
    static func toLRC(_ ttml: String) -> String? {
        guard let lines = parse(ttml) else { return nil }
        return lines.map { "\(stamp($0.time))\($0.text)" }.joined(separator: "\n")
    }

    /// Full parse, word stamps included.
    static func parse(_ ttml: String) -> [LyricLine]? {
        guard let data = ttml.data(using: .utf8) else { return nil }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse(), !delegate.lines.isEmpty else { return nil }
        return delegate.lines
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var lines: [LyricLine] = []

        /// Global shift declared by `<audio lyricOffset="…">`.
        private var offset: Double = 0
        private var inParagraph = false
        private var start: Double?
        private var buffer = ""
        /// Depth of nested elements inside a span we're ignoring.
        private var skipping = 0
        /// Per-word stamps for the paragraph being read, and the span currently open.
        private var words: [LyricWord] = []
        private var spanStart: Double?
        private var spanEnd: Double?
        private var spanText = ""

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes attrs: [String: String]) {
            let tag = name.components(separatedBy: ":").last ?? name

            if tag == "audio", let value = attrs["lyricOffset"], let d = Double(value) {
                offset = d
            }

            if skipping > 0 {
                skipping += 1
                return
            }

            switch tag {
            case "p":
                inParagraph = true
                buffer = ""
                words = []
                start = attrs["begin"].flatMap(TTML.seconds)
            case "span" where inParagraph:
                // Background vocals, translations and romanisations are separate
                // display tracks — never part of the line's own text.
                let role = attrs["ttm:role"] ?? attrs["role"] ?? ""
                if role == "x-bg" || role == "x-translation" || role == "x-roman" {
                    skipping = 1
                    return
                }
                let begin = attrs["begin"].flatMap(TTML.seconds)
                if start == nil, let begin {
                    // Some exports omit line-level timing; fall back to the
                    // earliest word stamp inside the line.
                    start = begin
                }
                spanStart = begin
                spanEnd = attrs["end"].flatMap(TTML.seconds)
                spanText = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inParagraph, skipping == 0 else { return }
            // Whitespace between spans is what separates the words, so keep it.
            buffer += string
            if spanStart != nil { spanText += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName: String?) {
            let tag = name.components(separatedBy: ":").last ?? name

            if skipping > 0 {
                skipping -= 1
                return
            }

            if tag == "span", inParagraph {
                // A syllable closes: bank it, with the next word's start as the
                // end when the export left `end` off.
                let body = spanText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let begin = spanStart, !body.isEmpty {
                    words.append(LyricWord(text: body,
                                           start: begin + offset,
                                           end: (spanEnd ?? begin) + offset))
                }
                spanStart = nil
                spanEnd = nil
                spanText = ""
                return
            }
            guard tag == "p" else { return }

            inParagraph = false
            let text = buffer
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let start, !text.isEmpty {
                lines.append(LyricLine(time: start + offset, text: text,
                                       words: TTML.sealed(words)))
            }
            start = nil
            buffer = ""
            words = []
        }
    }

    /// Give every word a sane end: exports often stamp only `begin`, which would
    /// leave zero-length syllables that never light up.
    private static func sealed(_ words: [LyricWord]) -> [LyricWord] {
        guard words.count > 1 else { return words }
        return words.enumerated().map { i, word in
            guard word.end <= word.start else { return word }
            let next = i + 1 < words.count ? words[i + 1].start : word.start + 0.35
            return LyricWord(text: word.text, start: word.start, end: max(next, word.start + 0.05))
        }
    }

    // MARK: Time

    /// TTML clock values: `12.5`, `1:23.45`, `1:02:03.4`, `500ms`, `5s`, `2m`, `1h`.
    static func seconds(_ raw: String) -> Double? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }

        if t.contains(":") {
            let parts = t.split(separator: ":").map(String.init)
            let values = parts.map { Double($0) ?? 0 }
            switch values.count {
            case 2: return values[0] * 60 + values[1]
            case 3: return values[0] * 3600 + values[1] * 60 + values[2]
            default: return nil
            }
        }
        if t.hasSuffix("ms") { return Double(t.dropLast(2)).map { $0 / 1000 } }
        if t.hasSuffix("h") { return Double(t.dropLast()).map { $0 * 3600 } }
        if t.hasSuffix("m") { return Double(t.dropLast()).map { $0 * 60 } }
        if t.hasSuffix("s") { return Double(t.dropLast()) }
        return Double(t)
    }

    private static func stamp(_ time: Double) -> String {
        let ms = Int((max(time, 0) * 1000).rounded())
        return String(format: "[%02d:%02d.%02d]", ms / 60000, (ms % 60000) / 1000, (ms % 1000) / 10)
    }
}
