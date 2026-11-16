import Foundation

/// Finding the same song on YouTube Music from its title and artists, as playlist imports and song
/// recognition need: the same title (once "(feat. …)", "- Remastered" and the like are set aside)
/// and one of the same artists, then the nearest length when there is one. Length alone let
/// another song by the artist, or somebody's cover, win whenever it ran about as long.
enum SongMatch {
    static let toleranceSeconds = 8.0
    /// An album cut and a single edit of one song can differ by more than a few seconds; with the
    /// title and an artist both the same, half a minute is allowed.
    static let sameNamesToleranceSeconds = 30.0

    /// The searches worth running for a song: the plain title with the first artist (a version tail
    /// such as "- 2022 Remaster" sends a search elsewhere), then everything as given.
    static func queries(title: String, artists: String) -> [String] {
        let firstArtist = splitArtistNames(artists).first ?? ""
        var seen = Set<String>()
        return [[searchTitle(title), firstArtist], [title, artists]]
            .map { $0.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ") }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The best result among [results] for [title] by [artists], or nil when none is the same song.
    /// [seconds] of 0 or less means the length is unknown and names alone decide.
    static func pick(_ results: [Track], title: String, artists: String, seconds: Double) -> Track? {
        guard !results.isEmpty else { return nil }
        let wantTitle = normalize(title)
        let wantArtists = splitArtists(artists)
        let same = results.filter { item in
            titleMatches(wantTitle, normalize(item.title))
                && artistMatches(wantArtists, splitArtists(item.artist))
        }
        guard seconds > 0 else { return same.first }
        return same
            .filter { $0.duration > 0 }
            .map { ($0, abs($0.duration - seconds)) }
            .filter { item, gap in
                gap <= toleranceSeconds
                    || (gap <= sameNamesToleranceSeconds && normalize(item.title) == wantTitle
                        && !item.artist.isEmpty && !wantArtists.isEmpty)
            }
            // When the request names no version, a "Live", "Remix" or "Re-Recorded" result is the
            // last choice among those that fit.
            .min { a, b in
                score(a.0, a.1, wanted: title) < score(b.0, b.1, wanted: title)
            }?.0
    }

    private static func score(_ item: Track, _ gap: Double, wanted: String) -> Double {
        gap + (marksVersion(item.title) && !marksVersion(wanted) ? 1000 : 0)
    }

    /// The title as people would type it: no remaster, soundtrack or featuring tail.
    static func searchTitle(_ title: String) -> String {
        var t = title.replacingOccurrences(of: #"\s*[(\[](feat|ft|with)\.?[^)\]]*[)\]]"#, with: "",
                                           options: [.regularExpression, .caseInsensitive])
        if let dash = t.range(of: " - "),
           matches(versionWords, String(t[dash.lowerBound...]).lowercased()) {
            t = String(t[..<dash.lowerBound])
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func normalize(_ text: String) -> String {
        var t = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        // "(feat. X)", "[Live]" and the like.
        t = t.replacingOccurrences(of: #"[(\[][^)\]]*[)\]]"#, with: " ", options: .regularExpression)
        // "Title - 2011 Remaster", "Title - Radio Edit".
        if let dash = t.range(of: " - "), matches(versionWords, String(t[dash.lowerBound...])) {
            t = String(t[..<dash.lowerBound])
        }
        t = t.replacingOccurrences(of: #"\b(feat|ft)\.?\s.*$"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static let versionWords =
        #"\b(remaster(ed)?|version|edit|mix|live|mono|stereo|from|feat|ft|with|acoustic|radio|bonus|deluxe|soundtrack|original|theme)\b"#
    private static let versionMark =
        #"\b(live|re-?recorded|remix|karaoke|instrumental|cover|sped up|slowed|acoustic|demo)\b"#
    /// Words after a title that say which version it is.
    private static let versionTail: Set<String> = [
        "remix", "remastered", "remaster", "version", "edit", "mix", "live", "mono", "stereo",
        "acoustic", "radio", "original", "theme", "soundtrack", "extended", "single", "album",
    ]

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func marksVersion(_ title: String) -> Bool { matches(versionMark, title) }

    private static func splitArtistNames(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .flatMap { $0.components(separatedBy: " feat. ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func splitArtists(_ text: String) -> [String] {
        let separators = #",|&| and | x |;|•|\bfeat\.?|\bft\.?"#
        let marked = text.replacingOccurrences(of: separators, with: "\u{1F}",
                                               options: [.regularExpression, .caseInsensitive])
        return marked.components(separatedBy: "\u{1F}").map(normalize).filter { !$0.isEmpty }
    }

    private static func titleMatches(_ want: String, _ have: String) -> Bool {
        if want.isEmpty || have.isEmpty { return want == have }
        if want == have { return true }
        // One title running on past the other counts only when what follows names a version
        // ("despacito remix"); "ghostbusters afterlife theme" is not "ghostbusters".
        let (short, long) = want.count <= have.count ? (want, have) : (have, want)
        if long.hasPrefix(short + " ") {
            let rest = long.dropFirst(short.count + 1).split(separator: " ").map(String.init)
            if rest.allSatisfy({ versionTail.contains($0) }) { return true }
        }
        let a = Set(want.split(separator: " ").map(String.init))
        let b = Set(have.split(separator: " ").map(String.init))
        return Double(a.intersection(b).count) / Double(a.union(b).count) >= 0.6
    }

    private static func artistMatches(_ want: [String], _ have: [String]) -> Bool {
        // Nothing to compare on one side: the title and the length have to do.
        if want.isEmpty || have.isEmpty { return true }
        return want.contains { w in have.contains { h in h == w || h.contains(w) || w.contains(h) } }
    }
}
