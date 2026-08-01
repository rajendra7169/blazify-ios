import Foundation

/// One synced lyric line.
/// One timed syllable inside a line. Only providers that serve word-level TTML
/// (Apple Music, Better Lyrics) fill these in; everything else leaves them empty
/// and the line simply animates as a whole.
struct LyricWord: Equatable {
    let text: String
    let start: Double
    let end: Double
}

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: Double   // seconds
    let text: String
    /// Empty unless the provider gave per-word stamps.
    var words: [LyricWord] = []
    /// TTML `ttm:agent` — who sings the line. Duets carry two, which is what
    /// "respect agent positioning" aligns to opposite sides.
    var agent: String? = nil

    var hasWordTimings: Bool { words.count > 1 }

    /// How far through this line the given moment is, 0…1, using the word
    /// stamps when we have them.
    func progress(at position: Double) -> Double {
        guard let first = words.first, let last = words.last, last.end > first.start else {
            return position >= time ? 1 : 0
        }
        return min(max((position - first.start) / (last.end - first.start), 0), 1)
    }
}

struct LyricsResult: Equatable {
    let lines: [LyricLine]   // empty when only plain lyrics exist
    let plain: String?
    let synced: Bool
    /// The original LRC text, kept so downloads can cache and re-parse it.
    var raw: String?

    /// Whether any line carries per-word stamps — what the word-by-word
    /// highlight and the Blazify renderer need.
    var hasWordTimings: Bool { lines.contains { $0.hasWordTimings } }
}

/// One candidate in the source picker, tagged with the provider it came from.
struct LyricsCandidate: Identifiable, Equatable {
    let id = UUID()
    let provider: String
    let trackName: String
    let artistName: String
    let result: LyricsResult
    /// How well this matched the song we asked for — see `Lyrics.matchScore`.
    /// Higher wins, and it outranks provider preference: a well-matched LrcLib
    /// result beats a badly-matched Apple one.
    var score: Double = 0

    var synced: Bool { result.synced }

    /// First lines with the `[mm:ss.xx]` stamps stripped, for the picker preview.
    var preview: String {
        let body = result.raw ?? result.plain ?? ""
        return body
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: " · ")
    }

    /// Majority script of the text, e.g. "Devanagari" / "Roman" — a language hint.
    var script: String? { Lyrics.detectScript(result.raw ?? result.plain ?? "") }
}

/// Multi-source lyrics — five providers: Apple Music
/// (via Paxsenix), BetterLyrics, LrcLib, KuGou and YouTube Music's own. None
/// needs an account, so all five are queried concurrently and every candidate
/// is offered in the picker.
enum Lyrics {
    static let sourceName = "LrcLib"   // shown until a provider is resolved

    // MARK: Fan-out

    /// Every candidate from every provider, best-first.
    /// `videoId` unlocks YouTube's own lyrics when known.
    static func search(title: String, artist: String, videoId: String = "",
                       duration: Double = 0) async -> [LyricsCandidate] {
        // Settings → Lyrics → Providers decides who gets asked at all. Reading
        // the flags up front keeps the fan-out itself unconditional.
        let prefs = await MainActor.run { LyricsPrefs.shared.snapshot() }

        async let lrc = prefs.contains(.lrcLib)
            ? lrcLib(title: title, artist: artist, duration: duration) : [LyricsCandidate]()
        async let kugou = prefs.contains(.kuGou)
            ? kuGou(title: title, artist: artist, duration: duration) : [LyricsCandidate]()
        async let apple = prefs.contains(.appleMusic)
            ? appleMusic(title: title, artist: artist, duration: duration) : [LyricsCandidate]()
        async let yt = prefs.contains(.youTube)
            ? youTube(videoId: videoId, title: title, artist: artist) : [LyricsCandidate]()
        async let better = prefs.contains(.betterLyrics)
            ? betterLyrics(title: title, artist: artist,
                           videoId: videoId, duration: duration)
            : [LyricsCandidate]()
        async let plus = prefs.contains(.lyricsPlus)
            ? lyricsPlus(title: title, artist: artist, duration: duration) : [LyricsCandidate]()
        let all = await apple + better + lrc + kugou + yt + plus
        // Match quality first — that's what stops a confident-but-wrong result
        // from a preferred provider winning. Then synced, then provider rank.
 // Provider order decides outright — the first
        // provider that answers wins outright. Every provider already scores its
        // OWN candidates and drops contradicted ones, so scoring is what picks
        // the right release; using it to re-rank ACROSS providers quietly
        // overruled the order set in Settings, which is how a song ended up on
 // LrcLib's line-level words when Apple had word-level ones.
        return all.enumerated().sorted { a, b in
            let ra = prefs.rank(a.element.provider), rb = prefs.rank(b.element.provider)
            if ra != rb { return ra < rb }
            if a.element.score != b.element.score { return a.element.score > b.element.score }
            if a.element.synced != b.element.synced { return a.element.synced }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// How well a search result matches the song we actually want. Ported from
    /// Paxsenix's `scoreAndFilterResults`: duration dominates, then the title,
    /// then the artist, with penalties for remix/mixed versions we didn't ask
    /// for. `duration` and `resultDuration` are seconds; 0 means unknown.
    static func matchScore(resultTitle: String, resultArtist: String, resultDuration: Double,
                           title: String, artist: String, duration: Double) -> Double {
        var score = 0.0

        func strip(_ s: String) -> String {
            s.replacingOccurrences(of: #"\s*\(.*?\)|\s*\[.*?\]"#, with: "",
                                   options: .regularExpression)
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
        }
        let wantTitle = strip(title)
        let gotTitle = strip(resultTitle)
        let wantArtist = cleanArtist(artist).lowercased()
        let gotArtist = resultArtist.lowercased()

        if duration > 0, resultDuration > 0 {
            let diff = abs(resultDuration - duration)
            if diff <= 2 { score += 100 }
            else if diff <= 5 { score += 50 }
            else if diff <= 10 { score += 10 }
            else { score -= 50 }        // almost certainly a different cut
        }

        if !wantTitle.isEmpty, !gotTitle.isEmpty {
            if gotTitle == wantTitle {
                score += 80
            } else if gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle) {
                score += 40
            }
        }

        if resultTitle.localizedCaseInsensitiveContains("mixed"),
           !title.localizedCaseInsensitiveContains("mixed") { score -= 60 }
        if resultTitle.localizedCaseInsensitiveContains("remix"),
           !title.localizedCaseInsensitiveContains("remix") { score -= 40 }

        if !wantArtist.isEmpty {
            if gotArtist.contains(wantArtist) {
                score += 50
            } else {
                let words = wantArtist.split(separator: " ").filter { $0.count > 2 }
                if words.contains(where: { gotArtist.contains($0) }) { score += 25 }
            }
        }
        return score
    }

    /// Clean up a title that came from a FILENAME rather than a catalogue.
    /// Imported files arrive as "03 - Song_Name (Official Video) [320kbps]", and
    /// searching that verbatim matches nothing — which is how a song ends up
    /// wearing another song's lyrics, since the best of a bad set still wins.
    static func fileTitle(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "_", with: " ")
        let rules: [(String, String)] = [
            // A leading track number: "03 - ", "03. ", "03 "
            (#"^\s*\d{1,3}\s*[-.)]?\s+"#, ""),
            // Bracketed noise, but only when it's noise — "(Live)" and
            // "(Acoustic)" are part of the song and change the lyrics.
            (#"\s*[(\[][^)\]]*(official|video|audio|lyrics?|kbps|mp3|hq|hd|full song|www\.|\.com|\.in|download|remaster)[^)\]]*[)\]]"#, ""),
            (#"\s*[-–]\s*(128|192|256|320)\s*kbps"#, ""),
            (#"\s*[-–]\s*(youtube|spotify|pagalworld|songspk)\b.*$"#, ""),
            (#"\s{2,}"#, " "),
        ]
        for (pattern, replacement) in rules {
            s = s.replacingOccurrences(of: pattern, with: replacement,
                                       options: [.regularExpression, .caseInsensitive])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How good a match has to be before we'll put it on an IMPORTED song.
    /// Catalogue songs carry an exact title and artist, so their top result is
    /// trustworthy; a file's title is whatever someone named it. With no artist
    /// at all we insist on the duration agreeing, because a title alone matches
    /// half the covers ever recorded.
    ///
    /// Reference points from `matchScore`: duration within 2s = 100, within
    /// 5s = 50, exact title = 80, artist = 50, an unverifiable provider = 45.
    static func importedFloor(artist: String) -> Double {
        artist.trimmingCharacters(in: .whitespaces).isEmpty ? 90 : 50
    }

    /// Providers that match server-side and hand back a single answer, so we
    /// can't score their result — treat them as a reasonable-but-not-verified
    /// match, below a duration-confirmed hit and above a contradicted one.
    private static let unverifiedScore: Double = 45

    /// The provider set and priority as chosen in Settings, captured so the
    /// concurrent fan-out never touches main-actor state.
    struct ProviderPrefs: Sendable {
        let active: [String]

        func contains(_ provider: LyricsProvider) -> Bool {
            active.contains(provider.rawValue)
        }

        /// Lower is better; anything not in the list sorts last.
        func rank(_ provider: String) -> Int {
            active.firstIndex { $0.caseInsensitiveCompare(provider) == .orderedSame }
                ?? active.count
        }
    }

    /// The one to show without being asked. `floor` is how well it has to match
    /// before we'll put it on the song unprompted — 0 for catalogue songs, whose
    /// title and artist are exact, and higher for imported files. Below the
    /// floor we show nothing rather than somebody else's words; the candidates
    /// are all still there for the version picker.
    static func best(_ candidates: [LyricsCandidate], floor: Double = 0) -> LyricsResult? {
        let usable = floor > 0 ? candidates.filter { $0.score >= floor } : candidates
        return usable.first(where: { $0.synced })?.result ?? usable.first?.result
    }

    // MARK: BetterLyrics (word-level TTML, no account)

 /// Deliberately queries the *exact* title and artist: normalising them tends
    /// to match a different cut of the song (radio
    /// edit vs original) whose timings then drift against what's playing.
    private static func betterLyrics(title: String, artist: String,
                                     videoId: String, duration: Double) async -> [LyricsCandidate] {
        guard !title.isEmpty, !artist.isEmpty else { return [] }

        var comps = URLComponents(string: "https://lyrics-api.boidu.dev/getLyrics")!
        var items = [URLQueryItem(name: "s", value: title), URLQueryItem(name: "a", value: artist)]
        if duration > 0 { items.append(URLQueryItem(name: "d", value: String(Int(duration)))) }
        comps.queryItems = items
        guard let url = comps.url else { return [] }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        // A miss comes back as 401, not 404 — anything non-200 just means no match.
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ttml = json["ttml"] as? String, !ttml.isEmpty,
              // Parse the TTML directly rather than round-tripping through LRC:
              // the per-word stamps are what the word-by-word animations and the
              // Blazify renderer run on, and LRC can't carry them.
              let lines = TTML.parse(ttml), !lines.isEmpty
        else { return [] }

        let lrc = TTML.toLRC(ttml) ?? ""
        // Matched server-side on the exact title/artist/duration we sent, and
        // its 401-on-miss means a 200 is already a confirmation.
        return [LyricsCandidate(provider: "BetterLyrics", trackName: title, artistName: artist,
                                result: LyricsResult(lines: lines, plain: nil, synced: true, raw: lrc),
                                score: duration > 0 ? 90 : unverifiedScore)]
    }

    // MARK: LyricsPlus (word-level, community-run mirrors)

 /// LyricsPlus hands back per-syllable
    /// stamps in milliseconds, which is the same shape TTML gives us — so this
    /// is a second word-by-word source for songs Apple doesn't carry.
    private static func lyricsPlus(title: String, artist: String,
                                   duration: Double) async -> [LyricsCandidate] {
        guard !title.isEmpty, !artist.isEmpty else { return [] }
        // Community-run, so any one of them can be down; try them in turn
 // rather than treating a dead mirror as "no lyrics".
        let mirrors = ["https://lyricsplus.prjktla.my.id",
                       "https://lyricsplus.binimum.org",
                       "https://lyricsplus-seven.vercel.app"]

        for host in mirrors {
            guard var comps = URLComponents(string: host + "/v2/lyrics/get") else { continue }
            var items = [URLQueryItem(name: "title", value: title),
                         URLQueryItem(name: "artist", value: artist)]
            if duration > 0 {
                items.append(URLQueryItem(name: "duration", value: String(Int(duration))))
            }
            comps.queryItems = items
            guard let url = comps.url,
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json["lyrics"] as? [[String: Any]], !rows.isEmpty
            else { continue }

            // "Word" means the syllable stamps are present; anything else is
            // line-level and the words array stays empty, as with LrcLib.
            let byWord = (json["type"] as? String)?
                .caseInsensitiveCompare("Word") == .orderedSame

            var lines: [LyricLine] = []
            for row in rows {
                guard let start = milliseconds(row["time"]) else { continue }
                let text = (row["text"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { continue }

                var words: [LyricWord] = []
                if byWord, let syllables = row["syllabus"] as? [[String: Any]] {
                    for syllable in syllables {
                        guard let begin = milliseconds(syllable["time"]),
                              let body = (syllable["text"] as? String)?
                                  .trimmingCharacters(in: .whitespacesAndNewlines),
                              !body.isEmpty
                        else { continue }
                        let length = milliseconds(syllable["duration"]) ?? 0
                        words.append(LyricWord(text: body, start: begin,
                                               end: begin + max(length, 0.05)))
                    }
                }
                let agent = (row["element"] as? [String: Any])?["singer"] as? String
                lines.append(LyricLine(time: start, text: text, words: words, agent: agent))
            }
            guard !lines.isEmpty else { continue }

            return [LyricsCandidate(provider: "LyricsPlus", trackName: title, artistName: artist,
                                    result: LyricsResult(lines: lines, plain: nil, synced: true,
                                                         raw: asLRC(lines)),
                                    // Matched server-side on title, artist and
                                    // duration, so a 200 is already a confirmation.
                                    score: duration > 0 ? 90 : unverifiedScore)]
        }
        return []
    }

    /// Milliseconds off a JSON number, in seconds.
    private static func milliseconds(_ value: Any?) -> Double? {
        if let d = value as? Double { return d / 1000 }
        if let n = value as? NSNumber { return n.doubleValue / 1000 }
        return nil
    }

    /// A line-level LRC rendering, so a downloaded song can cache these lyrics
    /// the same way it caches LrcLib's. The word stamps don't survive the trip —
    /// LRC can't carry them — but the sync does.
    private static func asLRC(_ lines: [LyricLine]) -> String {
        lines.map { line in
            let hundredths = Int((line.time * 100).rounded())
            return String(format: "[%02d:%02d.%02d]%@",
                          hundredths / 6000, (hundredths / 100) % 60,
                          hundredths % 100, line.text)
        }.joined(separator: "\n")
    }

    // MARK: LrcLib

    private static func lrcLib(title: String, artist: String,
                               duration: Double) async -> [LyricsCandidate] {
        let t = cleanTitle(title)
        let a = cleanArtist(artist)

        var attempts: [[URLQueryItem]] = []
        if !t.isEmpty, !a.isEmpty {
            attempts.append([.init(name: "track_name", value: t), .init(name: "artist_name", value: a)])
        }
        if !t.isEmpty { attempts.append([.init(name: "track_name", value: t)]) }
        if !t.isEmpty, !a.isEmpty { attempts.append([.init(name: "q", value: "\(a) \(t)")]) }
        if !t.isEmpty { attempts.append([.init(name: "q", value: t)]) }

        for items in attempts {
            let candidates = await lrcLibRequest(items, title: title, artist: artist,
                                                 duration: duration)
            if !candidates.isEmpty { return candidates }
        }
        return []
    }

    private static func lrcLibRequest(_ items: [URLQueryItem], title: String, artist: String,
                                      duration: Double) async -> [LyricsCandidate] {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = items
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Blazify iOS (github.com/rajendra7169/blazify-ios)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        var out: [LyricsCandidate] = []
        for item in arr {
            let name = item["trackName"] as? String ?? ""
            let by = item["artistName"] as? String ?? ""
            // LrcLib returns its own duration, so score each hit rather than
            // trusting search order — several same-name cuts come back at once.
            let itemDuration = (item["duration"] as? Double)
                ?? (item["duration"] as? NSNumber)?.doubleValue ?? 0
            let score = matchScore(resultTitle: name, resultArtist: by,
                                   resultDuration: itemDuration,
                                   title: title, artist: artist, duration: duration)
            guard score > 0 else { continue }

            if let lrc = item["syncedLyrics"] as? String, !lrc.isEmpty {
                out.append(LyricsCandidate(provider: "LrcLib", trackName: name, artistName: by,
                                           result: LyricsResult(lines: parseLRC(lrc),
                                                                plain: item["plainLyrics"] as? String,
                                                                synced: true, raw: lrc),
                                           score: score))
            } else if let plain = item["plainLyrics"] as? String, !plain.isEmpty {
                out.append(LyricsCandidate(provider: "LrcLib", trackName: name, artistName: by,
                                           result: LyricsResult(lines: [], plain: plain,
                                                                synced: false, raw: nil),
                                           score: score))
            }
        }
        return out.sorted { $0.score > $1.score }
    }

    // MARK: Apple Music (anonymous web token → catalog search → lyrics relay)

    /// Apple's public web player hands out a developer token to anyone; no
    /// account is involved. Cached until a request is rejected.
    private static var appleToken: String?

    private static func fetchAppleToken() async -> String? {
        if let appleToken { return appleToken }
        guard let home = URL(string: "https://beta.music.apple.com"),
              let (html, _) = try? await URLSession.shared.data(from: home),
              let page = String(data: html, encoding: .utf8),
              let bundleRange = page.range(of: #"/assets/index~[^"']+?\.js"#, options: .regularExpression)
        else { return nil }

        guard let js = URL(string: "https://beta.music.apple.com" + page[bundleRange]),
              let (data, _) = try? await URLSession.shared.data(from: js),
              let script = String(data: data, encoding: .utf8),
              let tokenRange = script.range(
                  of: #"eyJ[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+"#,
                  options: .regularExpression)
        else { return nil }

        appleToken = String(script[tokenRange])
        return appleToken
    }

    private static func appleMusic(title: String, artist: String,
                                   duration: Double) async -> [LyricsCandidate] {
        guard let token = await fetchAppleToken() else { return [] }
        let term = "\(cleanTitle(title)) \(cleanArtist(artist))"
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://amp-api.music.apple.com/v1/catalog/us/search?term=\(encoded)&types=songs&limit=5&l=en-US&platform=web")
        else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        req.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:95.0) Gecko/20100101 Firefox/95.0",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return [] }
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            appleToken = nil   // scraped token expired; next call re-scrapes
            return []
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let songs = (results["songs"] as? [String: Any])?["data"] as? [[String: Any]]
        else { return [] }

        // Score every hit before trusting any of them: Apple's search happily
        // returns remixes, unplugged cuts and same-name songs by other artists.
        let scored: [(id: String, attrs: [String: Any], score: Double)] = songs.compactMap { song in
            guard let id = song["id"] as? String else { return nil }
            let attrs = song["attributes"] as? [String: Any] ?? [:]
            let seconds = ((attrs["durationInMillis"] as? Double)
                           ?? (attrs["durationInMillis"] as? NSNumber)?.doubleValue ?? 0) / 1000
            let score = matchScore(resultTitle: attrs["name"] as? String ?? "",
                                   resultArtist: attrs["artistName"] as? String ?? "",
                                   resultDuration: seconds,
                                   title: title, artist: artist, duration: duration)
            return score > 0 ? (id, attrs, score) : nil
        }.sorted { $0.score > $1.score }

        var out: [LyricsCandidate] = []
        for song in scored.prefix(2) {
            let id = song.id
            let attrs = song.attrs
            guard let lyricsURL = URL(string: "https://lyrics.paxsenix.org/apple-music/lyrics?id=\(id)")
            else { continue }
            var lyricsReq = URLRequest(url: lyricsURL)
            lyricsReq.setValue("Blazify iOS", forHTTPHeaderField: "User-Agent")
            guard let (body, _) = try? await URLSession.shared.data(for: lyricsReq),
                  let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else { continue }

            let name = attrs["name"] as? String ?? ""
            let by = attrs["artistName"] as? String ?? ""
            let lrc = payload["lrc"] as? String ?? ""
            // Apple also serves per-word stamps in `ttmlContent`, and we did use
            // them for a while — but the user prefers the plain line highlight,
            // so we deliberately read the flattened `lrc` instead. Don't "fix"
            // this back to ttmlContent: line-level here is the intended look.
            if !lrc.isEmpty {
                out.append(LyricsCandidate(provider: "Apple Music", trackName: name, artistName: by,
                                           result: LyricsResult(lines: parseLRC(lrc), plain: nil,
                                                                synced: true, raw: lrc),
                                           score: song.score))
            } else if let plain = payload["plain"] as? String, !plain.isEmpty {
                out.append(LyricsCandidate(provider: "Apple Music", trackName: name, artistName: by,
                                           result: LyricsResult(lines: [], plain: plain,
                                                                synced: false, raw: nil),
                                           score: song.score))
            }
        }
        return out
    }

    // MARK: YouTube Music (plain lyrics, credited to their upstream source)

    private static func youTube(videoId: String, title: String, artist: String) async -> [LyricsCandidate] {
        guard !videoId.isEmpty, let found = await YouTube.lyrics(videoId: videoId) else { return [] }
        // Keyed on the videoId itself, so this is always the right song.
        return [LyricsCandidate(provider: found.source, trackName: title, artistName: artist,
                                result: LyricsResult(lines: [], plain: found.text,
                                                     synced: false, raw: nil),
                                score: 95)]
    }

    // MARK: KuGou (search → candidates by hash → base64 LRC)

    private static func kuGou(title: String, artist: String,
                              duration: Double) async -> [LyricsCandidate] {
        let keyword = "\(cleanTitle(title)) - \(cleanArtist(artist))"
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return [] }

        let searchURL = "https://mobileservice.kugou.com/api/v3/search/song?version=9108&plat=0&pagesize=8&showtype=0&keyword=\(encoded)"
        guard let songs = await kuGouJSON(searchURL),
              let data = songs["data"] as? [String: Any],
              let info = data["info"] as? [[String: Any]]
        else { return [] }

        var out: [LyricsCandidate] = []
        for song in info.prefix(3) {
            guard let hash = song["hash"] as? String, !hash.isEmpty else { continue }
            guard let found = await kuGouJSON("https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&hash=\(hash)"),
                  let candidates = found["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let key = first["accesskey"] as? String
            else { continue }
            let id = "\(first["id"] ?? "")"
            guard let payload = await kuGouJSON(
                "https://lyrics.kugou.com/download?fmt=lrc&charset=utf8&client=pc&ver=1&id=\(id)&accesskey=\(key)"),
                let base64 = payload["content"] as? String,
                let decoded = Data(base64Encoded: base64),
                let lrc = String(data: decoded, encoding: .utf8)
            else { continue }

            let normalized = normalizeKuGou(lrc)
            guard !normalized.isEmpty else { continue }
            let kugouName = song["songname"] as? String ?? ""
            let kugouArtist = song["singername"] as? String ?? ""
            out.append(LyricsCandidate(
                provider: "KuGou",
                trackName: kugouName,
                artistName: kugouArtist,
                result: LyricsResult(lines: parseLRC(normalized), plain: nil,
                                     synced: true, raw: normalized),
                score: max(matchScore(resultTitle: kugouName, resultArtist: kugouArtist,
                                      resultDuration: 0, title: title, artist: artist,
                                      duration: duration), 1)))
            if out.count >= 2 { break }
        }
        return out
    }

    private static func kuGouJSON(_ url: String) async -> [String: Any]? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Keep only timestamped lines and drop the credit block KuGou prepends.
    private static func normalizeKuGou(_ lrc: String) -> String {
        let stamped = lrc.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.range(of: #"^\[\d\d:\d\d\.\d{2,3}\]"#, options: .regularExpression) != nil }
        // Credit lines look like "[..] something : something".
        let credit = #"^\[[^\]]*\].+[:：].+$"#
        var lines = stamped
        if let lastCredit = lines.prefix(30).lastIndex(where: {
            $0.range(of: credit, options: .regularExpression) != nil
        }) {
            lines = Array(lines[(lastCredit + 1)...])
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Script detection (local, no API)

    /// Majority Unicode block of the text — a language hint for the picker.
    static func detectScript(_ text: String) -> String? {
        let body = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        var counts: [String: Int] = [:]
        for scalar in body.unicodeScalars {
            let v = scalar.value
            let label: String?
            switch v {
            case 0x0900...0x097F: label = "Devanagari"
            case 0x0A00...0x0A7F: label = "Gurmukhi"
            case 0x0980...0x09FF: label = "Bengali"
            case 0x0A80...0x0AFF: label = "Gujarati"
            case 0x0B00...0x0B7F: label = "Odia"
            case 0x0B80...0x0BFF: label = "Tamil"
            case 0x0C00...0x0C7F: label = "Telugu"
            case 0x0C80...0x0CFF: label = "Kannada"
            case 0x0D00...0x0D7F: label = "Malayalam"
            case 0x0600...0x06FF, 0x0750...0x077F: label = "Urdu"
            case 0x3040...0x30FF: label = "Japanese"
            case 0x4E00...0x9FFF: label = "Chinese"
            case 0xAC00...0xD7AF: label = "Korean"
            case 0x0400...0x04FF: label = "Cyrillic"
            case 0x0041...0x005A, 0x0061...0x007A: label = "Roman"
            default: label = nil
            }
            if let label { counts[label, default: 0] += 1 }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: Title cleaning

    private static func cleanTitle(_ s: String) -> String {
        var x = s
        x = x.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        x = x.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        x = x.replacingOccurrences(of: #"(?i)\s*[-–|]\s*(official.*|lyric.*|audio|video|visualizer|mix|remaster.*)\s*$"#,
                                   with: "", options: .regularExpression)
        x = x.replacingOccurrences(of: #"(?i)\s*\b(feat\.?|ft\.?|featuring)\b.*$"#, with: "", options: .regularExpression)
        return x.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanArtist(_ s: String) -> String {
        let noTopic = s.replacingOccurrences(of: #"(?i)\s*-\s*topic\s*$"#, with: "", options: .regularExpression)
        let first = noTopic.split(whereSeparator: { $0 == "," || $0 == "&" }).first.map(String.init) ?? noTopic
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse `[mm:ss.xx] text` LRC into sorted timestamped lines.
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#) else {
            return []
        }
        var out: [LyricLine] = []
        for raw in lrc.components(separatedBy: "\n") {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            for m in matches {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    frac = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                out.append(LyricLine(time: mm * 60 + ss + frac, text: text))
            }
        }
        return out.sorted { $0.time < $1.time }
    }
}

/// Remembers which source the user picked for a song, like the lyrics table.
enum LyricsStore {
    private static func key(_ videoId: String) -> String { "lyricsPick_\(videoId)" }

    static func save(_ candidate: LyricsCandidate, for videoId: String) {
        guard let body = candidate.result.raw ?? candidate.result.plain else { return }
        UserDefaults.standard.set(["provider": candidate.provider,
                                   "body": body,
                                   "synced": candidate.result.synced], forKey: key(videoId))
    }

    static func load(for videoId: String) -> (provider: String, result: LyricsResult)? {
        guard let dict = UserDefaults.standard.dictionary(forKey: key(videoId)),
              let provider = dict["provider"] as? String,
              let body = dict["body"] as? String else { return nil }
        let synced = dict["synced"] as? Bool ?? false
        return (provider, synced
                ? LyricsResult(lines: Lyrics.parseLRC(body), plain: nil, synced: true, raw: body)
                : LyricsResult(lines: [], plain: body, synced: false, raw: nil))
    }
}
