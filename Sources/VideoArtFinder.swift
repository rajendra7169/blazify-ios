import Foundation

/// Which video belongs behind a song: the rules alone, apart from the network,
/// so they can be read — and checked — without asking YouTube anything.
///
/// The order is the order of trust:
/// 1. the song is a video itself (handled by the caller);
/// 2. the artist's own video on YouTube Music, the one most watched and nearest
///    the song's length;
/// 3. a search of everyday YouTube, scored, for the many songs whose video was
///    never marked as official there;
/// 4. the artist's own lyric video, only when nothing else was found;
/// 5. nothing, and the cover shows.
///
/// A slowed-and-reverbed edit, a fan's lyric video, a festival performance or a
/// fan channel re-uploading the artist's video are what plain searches hand back
/// first, and none of them is the song's picture — most of what is here exists
/// to tell those apart.
enum VideoArtFinder {

    /// The song as the player knows it.
    struct Song {
        let title: String
        /// In the order they are credited; the first is the one searched for.
        let artists: [String]
        /// Seconds, or 0 when not known.
        let length: Double
    }

    /// One row of YouTube Music's video search.
    struct MusicRow {
        let videoId: String
        let title: String
        /// The first part of the row's second line, before the first "•": the
        /// artists, or the channel that uploaded it.
        let artist: String
        let views: Int
        /// Seconds, or 0 when the row carries none.
        let length: Double
        /// YouTube Music's mark for an artist's own video. Fan channels can
        /// carry it too, which is why the artist is checked as well.
        let isOfficial: Bool
    }

    /// One video from a search of everyday YouTube.
    struct WebRow {
        let videoId: String
        let title: String
        let channel: String
        /// The music note beside the channel name: an official artist channel.
        let artistBadge: Bool
        /// The tick beside the channel name (an artist channel has one too).
        let verified: Bool
        let views: Int
        /// Seconds, or 0 when not known.
        let length: Double
    }

    enum Via: String {
        case official, scored, lyric
    }

    /// The video chosen, and why.
    struct Pick {
        let videoId: String
        let title: String
        /// The artist line or channel it came from.
        let by: String
        let views: Int
        let length: Double
        let via: Via
        let score: Double
    }

    /// How many YouTube Music rows are looked through.
    static let musicCandidates = 10
    /// How many everyday YouTube results are looked through.
    static let everydayCandidates = 15
    /// The score an everyday YouTube video needs before it is trusted as the song's.
    static let enough = 5.5

    /// Words in a video's title that mean it is not the song's own video —
    /// unless the song's title has them too ("Live Forever", "Lyrics of Love").
    static let badWords = [
        "lyric", "lyrics", "lyrical", "slowed", "reverb", "sped up", "speed up", "8d", "bass boosted", "bass boost",
        "karaoke", "cover", "reaction", "status", "teaser", "trailer", "#shorts", "shorts", "jukebox", "full album",
        "audio", "visualizer", "visualiser", "remix", "live", "instrumental", "ringtone", "whatsapp", "mashup",
        "nightcore", "lofi", "lo-fi", "1 hour", "10 hours", "extended", "reply version", "female version", "male version",
        "making of", "behind the scenes", "dance cover", "tutorial", "guitar", "piano", "unplugged", "acoustic",
        "reprise", "version", "edit", "loop", "fanmade", "fan made", "amv", "tiktok", "trend", "challenge",
        "@", "festival", "performance", "concert", "choreography", "dance break", "dance practice", "fancam",
        "awards", "show", "stage", "clip", "8k", "4k",
    ]

    /// Phrases in a title that mean it is the video itself.
    static let goodWords = [
        "official video", "official music video", "music video", "full video", "video song", "(song)",
        "official mv", " mv", "m/v",
    ]

    private static let lyricWords: Set<String> = ["lyric", "lyrics", "lyrical"]

    // MARK: - The song

    /// The artist line split into names: "Arijit Singh & Shilpa Rao" is two.
    static func artists(in line: String) -> [String] {
        line.replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: "&", with: ",")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// What YouTube Music is asked: the whole title and the first artist.
    static func musicQuery(for song: Song) -> String {
        "\(song.title) \(song.artists.first ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What everyday YouTube is asked: the song's bare name and the first artist.
    static func everydayQuery(for song: Song) -> String {
        "\(coreTitle(song.title)) \(song.artists.first ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Step 2: the artist's own video on YouTube Music

    /// The artist's own video, when YouTube Music has one. When all it has is
    /// the artist's own lyric video, that comes back as `fallback` instead, to
    /// be used only if the everyday search finds nothing better.
    static func officialVideo(for song: Song, in rows: [MusicRow])
        -> (pick: Pick?, fallback: Pick?, notes: [String]) {
        let core = coreTitle(song.title)
        var notes: [String] = []
        var best: (row: MusicRow, score: Double, lyric: Bool)?
        var kept = 0

        for row in rows.prefix(musicCandidates) where row.isOfficial {
            // Marked official, but by whom: a fan channel can carry the mark too.
            let own = song.artists.contains { a in
                !a.isEmpty && (contains(a, in: row.artist) || contains(row.artist, in: a))
            }
            guard own else {
                notes.append("official: skip \(row.videoId) \"\(clip(row.title))\" (by \(row.artist), not the artist)")
                continue
            }
            guard contains(core, in: row.title) else {
                notes.append("official: skip \(row.videoId) \"\(clip(row.title))\" (another song)")
                continue
            }
            let bad = badWord(row.title, songTitle: song.title)
            let lyric = bad.map { lyricWords.contains($0) } ?? false
            if let bad, !lyric {
                notes.append("official: skip \(row.videoId) \"\(clip(row.title))\" (\(bad))")
                continue
            }
            kept += 1
            let near = song.length > 0 && row.length > 0 ? min(abs(row.length - song.length) / 60, 2) : 0
            // The artist's own lyric video only when there is nothing better, anywhere.
            let score = 0.8 * log10(Double(max(row.views, 1))) - near - (lyric ? 100 : 0)
            if best == nil || score > best!.score { best = (row, score, lyric) }
        }

        guard let best else {
            notes.append("official: none of \(min(rows.count, musicCandidates)) rows is the artist's own video")
            return (nil, nil, notes)
        }
        let pick = Pick(videoId: best.row.videoId, title: best.row.title, by: best.row.artist,
                        views: best.row.views, length: best.row.length,
                        via: best.lyric ? .lyric : .official, score: best.score)
        if best.lyric {
            notes.append("official: only the artist's lyric video, \(describe(pick, song)) — kept for last")
            return (nil, pick, notes)
        }
        notes.append("official: chose \(describe(pick, song)), best of \(kept)")
        return (pick, nil, notes)
    }

    // MARK: - Step 3: everyday YouTube, scored

    /// The song's video from a search of everyday YouTube, when one scores
    /// high enough to be trusted.
    static func everydayVideo(for song: Song, in rows: [WebRow]) -> (pick: Pick?, notes: [String]) {
        let core = coreTitle(song.title)
        let artists = song.artists.filter { !$0.isEmpty }
        // Labels shorten names in long titles ("Arijit S, Shilpa R"): a first
        // name of four letters or more is enough to count as named.
        let firsts = artists.compactMap { a -> String? in
            guard let first = words(a).first, first.unicodeScalars.count >= 4 else { return nil }
            return first
        }
        var notes: [String] = []
        var kept: [(row: WebRow, score: Double)] = []
        // The first few refusals say enough; the log is short and shared.
        var skipped = 0
        func skip(_ note: String) {
            skipped += 1
            if skipped <= 6 { notes.append(note) }
        }

        for (rank, row) in rows.prefix(everydayCandidates).enumerated() {
            guard !row.videoId.isEmpty, contains(core, in: row.title) else { continue }
            if let bad = badWord(row.title, songTitle: song.title) {
                skip("everyday: skip \"\(clip(row.title))\" (\(bad))")
                continue
            }
            if row.length > 0,
               row.length < 60 || (song.length > 0 && row.length > max(song.length * 2, song.length + 240)) {
                skip("everyday: skip \"\(clip(row.title))\" (length \(Int(row.length))s)")
                continue
            }
            let byArtist = artists.contains { contains($0, in: row.channel) }
            let titleWords = Set(words(row.title))
            let named = artists.contains { contains($0, in: row.title) }
                || firsts.contains { titleWords.contains($0) }
            guard byArtist || named else {
                skip("everyday: skip \"\(clip(row.title))\" (no artist)")
                continue
            }
            guard !(row.artistBadge && !byArtist) else {
                // Another artist's own channel: a cover, however it is titled.
                skip("everyday: skip \"\(clip(row.title))\" (another artist \(row.channel))")
                continue
            }
            let trusted = row.artistBadge || row.verified || fold(row.channel).contains("vevo")
            guard trusted else {
                skip("everyday: skip \"\(clip(row.title))\" (unverified \(row.channel))")
                continue
            }
            var score = row.artistBadge ? 4.0 : 2.0
            score += byArtist ? 3 : 0
            score += isGood(row.title) ? 2 : 0
            score += 0.6 * log10(Double(max(row.views, 1)))
            if song.length > 0 && row.length > 0 {
                score -= min(abs(row.length - song.length) / 60, 3)
            }
            score -= 0.05 * Double(rank)
            kept.append((row, score))
        }

        // The most watched trusted upload is usually the video itself.
        if let top = kept.map(\.row.views).max() {
            kept = kept.map { ($0.row, $0.score + ($0.row.views == top ? 1.5 : 0)) }
        }
        var best: (row: WebRow, score: Double)?
        for candidate in kept where best == nil || candidate.score > best!.score { best = candidate }

        guard let best else {
            notes.append("everyday: nothing trusted among \(min(rows.count, everydayCandidates)) results")
            return (nil, notes)
        }
        let pick = Pick(videoId: best.row.videoId, title: best.row.title, by: best.row.channel,
                        views: best.row.views, length: best.row.length, via: .scored, score: best.score)
        guard best.score >= enough else {
            notes.append("everyday: best was \(describe(pick, song)), under \(enough)")
            return (nil, notes)
        }
        notes.append("everyday: chose \(describe(pick, song)) of \(kept.count) trusted")
        return (pick, notes)
    }

    // MARK: - Text

    /// Lowercase, accents gone (é → e), "$" read as "s" and "&" as "and", and
    /// everything but letters, digits and spaces turned into spaces.
    static func fold(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.lowercased().decomposedStringWithCompatibilityMapping.unicodeScalars {
            if scalar.properties.canonicalCombiningClass != .notReordered { continue }
            switch scalar {
            case "$": out.append("s")
            case "&": out.append(contentsOf: " and ".unicodeScalars)
            default: out.append(isWordOrSpace(scalar) ? scalar : " ")
            }
        }
        return String(out)
    }

    private static func isWordOrSpace(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "_" || scalar.properties.isWhitespace || scalar.properties.numericType != nil { return true }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    static func words(_ text: String) -> [String] {
        fold(text).unicodeScalars
            .split(whereSeparator: { $0.properties.isWhitespace })
            .map { String(Substring($0)) }
    }

    /// The song's name without "(feat. …)", "[From …]", " - Remastered" and the like.
    static func coreTitle(_ title: String) -> String {
        var t = title.replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
        if let dash = t.range(of: #"\s+-\s+"#, options: .regularExpression) {
            t = String(t[..<dash.lowerBound])
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? title : t
    }

    /// The share of `needle`'s words found among `hay`'s.
    static func share(of needle: String, in hay: String) -> Double {
        let n = words(needle)
        guard !n.isEmpty else { return 0 }
        let h = Set(words(hay))
        return Double(n.filter { h.contains($0) }.count) / Double(n.count)
    }

    /// Every word of `needle` is in `hay`.
    static func contains(_ needle: String, in hay: String) -> Bool {
        share(of: needle, in: hay) >= 0.99
    }

    /// The first word that marks a video as not the song's own — one the
    /// video's title has and the song's does not — or nil.
    static func badWord(_ videoTitle: String, songTitle: String) -> String? {
        if videoTitle.contains("@") && !songTitle.contains("@") { return "@" }
        let video = " " + fold(videoTitle) + " "
        let song = " " + fold(songTitle) + " "
        for word in badWords where word != "@" {
            let padded = " " + fold(word).trimmingCharacters(in: .whitespaces) + " "
            if video.contains(padded) && !song.contains(padded) { return word }
        }
        return nil
    }

    static func isGood(_ videoTitle: String) -> Bool {
        let title = " " + fold(videoTitle) + " "
        return goodWords.contains { title.contains(fold($0)) }
    }

    // MARK: - Numbers on a row

    /// "2.1B views" → 2,100,000,000; "641,356,248 views" → 641,356,248; 0 when there is none.
    static func views(_ text: String) -> Int {
        let chars = Array(text.replacingOccurrences(of: ",", with: "").unicodeScalars)
        func isNumeral(_ c: Unicode.Scalar) -> Bool { ("0"..."9").contains(c) || c == "." }
        guard let start = chars.firstIndex(where: isNumeral) else { return 0 }
        var end = start
        while end < chars.count, isNumeral(chars[end]) { end += 1 }
        guard let number = Double(String(String.UnicodeScalarView(chars[start..<end]))) else { return 0 }
        var i = end
        while i < chars.count, chars[i].properties.isWhitespace { i += 1 }
        let scale: Double
        switch i < chars.count ? chars[i] : " " {
        case "K": scale = 1e3
        case "M": scale = 1e6
        case "B": scale = 1e9
        default: scale = 1
        }
        let value = number * scale
        guard value.isFinite, value >= 0, value < 9e18 else { return 0 }
        return Int(value)
    }

    /// "3:43" → 223, "1:02:03" → 3723: every number on the line, read as
    /// hours, minutes and seconds.
    static func seconds(_ text: String) -> Double {
        text.unicodeScalars
            .split(whereSeparator: { !("0"..."9").contains($0) })
            .compactMap { Double(String(Substring($0))) }
            .reduce(0) { $0 * 60 + $1 }
    }

    // MARK: - Notes

    private static func clip(_ text: String) -> String {
        text.count > 50 ? String(text.prefix(50)) + "…" : text
    }

    private static func shortViews(_ n: Int) -> String {
        switch n {
        case 1_000_000_000...: return String(format: "%.1fB", Double(n) / 1e9)
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1e6)
        case 1_000...: return String(format: "%.1fK", Double(n) / 1e3)
        default: return "\(n)"
        }
    }

    private static func describe(_ pick: Pick, _ song: Song) -> String {
        "\(pick.videoId) \"\(clip(pick.title))\" by \(pick.by), \(shortViews(pick.views)) views, "
            + "\(Int(pick.length))s for a \(Int(song.length))s song, score \(String(format: "%.1f", pick.score))"
    }
}
