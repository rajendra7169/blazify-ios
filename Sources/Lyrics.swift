import Foundation

/// One synced lyric line.
struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: Double   // seconds
    let text: String
}

struct LyricsResult: Equatable {
    let lines: [LyricLine]   // empty when only plain lyrics exist
    let plain: String?
    let synced: Bool
    /// The original LRC text, kept so downloads can cache and re-parse it.
    var raw: String?
}

/// One candidate in the source picker, tagged with the provider it came from.
struct LyricsCandidate: Identifiable, Equatable {
    let id = UUID()
    let provider: String
    let trackName: String
    let artistName: String
    let result: LyricsResult

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

/// Multi-source lyrics. Apple Music, LrcLib and KuGou all work without any
/// account, so all three are queried concurrently and every candidate is
/// offered in the picker.
enum Lyrics {
    static let sourceName = "LrcLib"   // shown until a provider is resolved

    // MARK: Fan-out

    /// Every candidate from every provider, best-first.
    static func search(title: String, artist: String) async -> [LyricsCandidate] {
        async let lrc = lrcLib(title: title, artist: artist)
        async let kugou = kuGou(title: title, artist: artist)
        async let apple = appleMusic(title: title, artist: artist)
        let all = await apple + lrc + kugou
        // Synced first, then by provider rank, preserving arrival order within a rank.
        return all.enumerated().sorted { a, b in
            if a.element.synced != b.element.synced { return a.element.synced }
            let ra = rank(a.element.provider), rb = rank(b.element.provider)
            if ra != rb { return ra < rb }
            return a.offset < b.offset
        }.map(\.element)
    }

    private static func rank(_ provider: String) -> Int {
        switch provider.lowercased() {
        case "apple music": return 0
        case "lrclib": return 1
        case "kugou": return 2
        default: return 3
        }
    }

    static func best(_ candidates: [LyricsCandidate]) -> LyricsResult? {
        candidates.first(where: { $0.synced })?.result ?? candidates.first?.result
    }

    // MARK: LrcLib

    private static func lrcLib(title: String, artist: String) async -> [LyricsCandidate] {
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
            let candidates = await lrcLibRequest(items)
            if !candidates.isEmpty { return candidates }
        }
        return []
    }

    private static func lrcLibRequest(_ items: [URLQueryItem]) async -> [LyricsCandidate] {
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
            if let lrc = item["syncedLyrics"] as? String, !lrc.isEmpty {
                out.append(LyricsCandidate(provider: "LrcLib", trackName: name, artistName: by,
                                           result: LyricsResult(lines: parseLRC(lrc),
                                                                plain: item["plainLyrics"] as? String,
                                                                synced: true, raw: lrc)))
            } else if let plain = item["plainLyrics"] as? String, !plain.isEmpty {
                out.append(LyricsCandidate(provider: "LrcLib", trackName: name, artistName: by,
                                           result: LyricsResult(lines: [], plain: plain,
                                                                synced: false, raw: nil)))
            }
        }
        return out
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

    private static func appleMusic(title: String, artist: String) async -> [LyricsCandidate] {
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

        var out: [LyricsCandidate] = []
        for song in songs.prefix(2) {
            guard let id = song["id"] as? String else { continue }
            let attrs = song["attributes"] as? [String: Any] ?? [:]
            guard let lyricsURL = URL(string: "https://lyrics.paxsenix.org/apple-music/lyrics?id=\(id)")
            else { continue }
            var lyricsReq = URLRequest(url: lyricsURL)
            lyricsReq.setValue("Blazify iOS", forHTTPHeaderField: "User-Agent")
            guard let (body, _) = try? await URLSession.shared.data(for: lyricsReq),
                  let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else { continue }

            let name = attrs["name"] as? String ?? ""
            let by = attrs["artistName"] as? String ?? ""
            if let lrc = payload["lrc"] as? String, !lrc.isEmpty {
                out.append(LyricsCandidate(provider: "Apple Music", trackName: name, artistName: by,
                                           result: LyricsResult(lines: parseLRC(lrc), plain: nil,
                                                                synced: true, raw: lrc)))
            } else if let plain = payload["plain"] as? String, !plain.isEmpty {
                out.append(LyricsCandidate(provider: "Apple Music", trackName: name, artistName: by,
                                           result: LyricsResult(lines: [], plain: plain,
                                                                synced: false, raw: nil)))
            }
        }
        return out
    }

    // MARK: KuGou (search → candidates by hash → base64 LRC)

    private static func kuGou(title: String, artist: String) async -> [LyricsCandidate] {
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
            out.append(LyricsCandidate(
                provider: "KuGou",
                trackName: song["songname"] as? String ?? "",
                artistName: song["singername"] as? String ?? "",
                result: LyricsResult(lines: parseLRC(normalized), plain: nil,
                                     synced: true, raw: normalized)))
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

/// Remembers which source the user picked for a song, like Android's lyrics table.
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
