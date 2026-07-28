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
}

/// One alternate lyrics version for the language/source picker.
struct LyricsCandidate: Identifiable {
    let id: Int
    let trackName: String
    let artistName: String
    let result: LyricsResult
    var synced: Bool { result.synced }
}

/// Lyrics from LrcLib (open synced-lyrics API, no auth). Tries several search
/// strategies — YT Music titles carry "(Official Video)", "feat.", "- Topic"
/// etc. that make a naive LrcLib lookup miss most songs.
enum Lyrics {
    static let sourceName = "LrcLib"

    static func search(title: String, artist: String) async -> [LyricsCandidate] {
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
            let candidates = await request(items)
            if !candidates.isEmpty { return candidates }
        }
        return []
    }

    static func best(_ candidates: [LyricsCandidate]) -> LyricsResult? {
        candidates.first(where: { $0.synced })?.result ?? candidates.first?.result
    }

    private static func request(_ items: [URLQueryItem]) async -> [LyricsCandidate] {
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
            let id = (item["id"] as? Int) ?? out.count
            let name = item["trackName"] as? String ?? ""
            let by = item["artistName"] as? String ?? ""
            if let lrc = item["syncedLyrics"] as? String, !lrc.isEmpty {
                out.append(LyricsCandidate(id: id, trackName: name, artistName: by,
                                           result: LyricsResult(lines: parseLRC(lrc),
                                                                plain: item["plainLyrics"] as? String,
                                                                synced: true)))
            } else if let plain = item["plainLyrics"] as? String, !plain.isEmpty {
                out.append(LyricsCandidate(id: id, trackName: name, artistName: by,
                                           result: LyricsResult(lines: [], plain: plain, synced: false)))
            }
        }
        return out
    }

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
