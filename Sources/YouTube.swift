import Foundation

/// Resolves a YouTube videoId to a playable audio URL **on-device**, using the
/// ANDROID_VR client plus a fetched visitorData.
///
/// This is how the Android app works and why it's reliable: from the phone's own
/// (residential) connection YouTube doesn't bot-check, and the ANDROID_VR client
/// returns the FULL audio (no 1-minute PoToken gate). The two things that make it
/// work: a *current* client version, and a visitorData sent as X-Goog-Visitor-Id.
enum YouTube {

    static let clientVersion = "1.65.10"
    static let ua = "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"

    /// visitorData is a short-lived session token; fetch once and reuse.
    private static var cachedVisitor: String?

    static func streamURL(for videoId: String) async -> URL? {
        let visitor = await visitorData()
        let body: [String: Any] = [
            "context": ["client": [
                "clientName": "ANDROID_VR", "clientVersion": clientVersion,
                "deviceMake": "Oculus", "deviceModel": "Quest 3",
                "androidSdkVersion": 32, "osName": "Android", "osVersion": "12L",
                "userAgent": ua, "hl": "en",
            ]],
            "videoId": videoId,
            "contentCheckOk": true, "racyCheckOk": true,
        ]
        guard
            let url = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"),
            let payload = try? JSONSerialization.data(withJSONObject: body)
        else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = payload
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("28", forHTTPHeaderField: "X-Youtube-Client-Name")
        req.setValue(clientVersion, forHTTPHeaderField: "X-Youtube-Client-Version")
        if let visitor { req.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id") }

        guard
            let (data, _) = try? await URLSession.shared.data(for: req),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let streaming = json["streamingData"] as? [String: Any],
            let formats = streaming["adaptiveFormats"] as? [[String: Any]]
        else { return nil }

        // Highest-bitrate audio/mp4 (AAC) with a direct url — itag 140 etc.
        var best: String?
        var bestRate = -1
        for f in formats {
            let mime = f["mimeType"] as? String ?? ""
            guard mime.hasPrefix("audio/mp4"), let u = f["url"] as? String, !u.isEmpty else { continue }
            let rate = (f["bitrate"] as? Int) ?? (f["averageBitrate"] as? Int) ?? 0
            if rate > bestRate { bestRate = rate; best = u }
        }
        guard let best else { return nil }
        return URL(string: best)
    }

    /// Fetch a visitorData from the homepage's ytcfg (cached for the session).
    private static func visitorData() async -> String? {
        if let cachedVisitor { return cachedVisitor }
        guard let url = URL(string: "https://www.youtube.com/") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("PREF=hl=en&tz=UTC; SOCS=CAI", forHTTPHeaderField: "Cookie")
        guard
            let (data, _) = try? await URLSession.shared.data(for: req),
            let html = String(data: data, encoding: .utf8),
            let start = html.range(of: "\"visitorData\":\"")
        else { return nil }
        let rest = html[start.upperBound...]
        guard let endQuote = rest.firstIndex(of: "\"") else { return nil }
        let vd = String(rest[..<endQuote])
        cachedVisitor = vd
        return vd
    }
}
