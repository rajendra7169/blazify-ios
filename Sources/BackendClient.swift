import Foundation

/// Resolves search results and stream URLs by calling YouTube's InnerTube API
/// directly from the device.
///
/// Why on-device instead of via a cloud extractor server: a server's datacenter IP
/// now gets "Sign in to confirm you're not a bot", so it can't resolve streams. The
/// phone's own residential IP isn't gated that way — so this is both more reliable
/// AND faster (no server hop, no free-tier cold start).
///
/// If playback/search ever breaks across the board with no obvious cause, YouTube
/// has most likely rejected these client versions (FAILED_PRECONDITION) — bump the
/// `clientVersion` strings (and matching user-agents) below.
enum BackendClient {

    private static let host = "https://youtubei.googleapis.com/youtubei/v1"
    private static let webKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    private static let iosKey = "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc"
    private static let webUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
    private static let iosUA = "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X)"

    // MARK: - Search

    static func search(_ query: String) async -> [Track] {
        let body: [String: Any] = [
            "context": ["client": [
                "clientName": "WEB", "clientVersion": "2.20240726.00.00",
                "hl": "en", "gl": "US",
            ]],
            "query": query,
        ]
        guard let json = await post("search", key: webKey, userAgent: webUA,
                                    origin: "https://www.youtube.com", body: body)
        else { return [] }
        return parseSearch(json)
    }

    // MARK: - Stream

    /// Resolve a videoId to a playable audio URL via YouTube's IOS client, which
    /// returns direct, un-throttled audio/mp4 URLs (iOS can't play WebM/Opus).
    static func streamURL(for videoId: String) async -> URL? {
        let body: [String: Any] = [
            "context": ["client": [
                "clientName": "IOS", "clientVersion": "20.10.4",
                "deviceMake": "Apple", "deviceModel": "iPhone16,2",
                "osName": "iPhone", "osVersion": "18.3.2.22D82",
                "hl": "en", "gl": "US",
            ]],
            "videoId": videoId,
            "contentCheckOk": true, "racyCheckOk": true,
        ]
        guard
            let json = await post("player", key: iosKey, userAgent: iosUA, origin: nil, body: body),
            let streaming = json["streamingData"] as? [String: Any],
            let formats = streaming["adaptiveFormats"] as? [[String: Any]]
        else { return nil }

        // Highest-bitrate audio/mp4 (AAC) with a direct url.
        var bestURL: String?
        var bestRate = -1
        for f in formats {
            let mime = f["mimeType"] as? String ?? ""
            guard mime.hasPrefix("audio/mp4"), let u = f["url"] as? String, !u.isEmpty else { continue }
            let rate = (f["bitrate"] as? Int) ?? (f["averageBitrate"] as? Int) ?? 0
            if rate > bestRate { bestRate = rate; bestURL = u }
        }
        guard let bestURL else { return nil }
        return URL(string: bestURL)
    }

    // MARK: - InnerTube POST

    private static func post(_ endpoint: String, key: String, userAgent: String,
                             origin: String?, body: [String: Any]) async -> [String: Any]? {
        guard
            let url = URL(string: "\(host)/\(endpoint)?prettyPrint=false&key=\(key)"),
            let payload = try? JSONSerialization.data(withJSONObject: body)
        else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = payload
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let origin { req.setValue(origin, forHTTPHeaderField: "Origin") }

        guard
            let (data, _) = try? await URLSession.shared.data(for: req),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    // MARK: - Search parsing

    private static func parseSearch(_ json: [String: Any]) -> [Track] {
        guard
            let contents = json["contents"] as? [String: Any],
            let two = contents["twoColumnSearchResultsRenderer"] as? [String: Any],
            let primary = two["primaryContents"] as? [String: Any],
            let sectionList = primary["sectionListRenderer"] as? [String: Any],
            let sections = sectionList["contents"] as? [[String: Any]]
        else { return [] }

        var out: [Track] = []
        for section in sections {
            guard
                let itemSection = section["itemSectionRenderer"] as? [String: Any],
                let items = itemSection["contents"] as? [[String: Any]]
            else { continue }
            for item in items {
                guard
                    let vr = item["videoRenderer"] as? [String: Any],
                    let videoId = vr["videoId"] as? String, !videoId.isEmpty
                else { continue }
                let owner = runsText(vr["ownerText"])
                let lengthText = (vr["lengthText"] as? [String: Any])?["simpleText"] as? String ?? ""
                let track = Track(
                    videoId: videoId,
                    title: runsText(vr["title"]),
                    artist: owner.isEmpty ? runsText(vr["longBylineText"]) : owner,
                    thumbnail: lastThumb(vr["thumbnail"]),
                    duration: parseDuration(lengthText)
                )
                out.append(track)
                if out.count >= 25 { return out }
            }
        }
        return out
    }

    /// YouTube renders text as either a `runs` array or a `simpleText`.
    private static func runsText(_ obj: Any?) -> String {
        guard let dict = obj as? [String: Any] else { return "" }
        if let runs = dict["runs"] as? [[String: Any]], let text = runs.first?["text"] as? String {
            return text
        }
        return dict["simpleText"] as? String ?? ""
    }

    private static func lastThumb(_ obj: Any?) -> String {
        guard
            let dict = obj as? [String: Any],
            let thumbs = dict["thumbnails"] as? [[String: Any]]
        else { return "" }
        return thumbs.last?["url"] as? String ?? ""
    }

    /// "3:45" / "1:02:03" -> seconds.
    private static func parseDuration(_ s: String) -> Double {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return Double(parts[0] * 3600 + parts[1] * 60 + parts[2])
        case 2: return Double(parts[0] * 60 + parts[1])
        case 1: return Double(parts[0])
        default: return 0
        }
    }
}
