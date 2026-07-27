import Foundation

/// Fully on-device YouTube access (no server), mirroring the Android Blazify app.
///
/// - Playback: the **VISIONOS** client — no PoToken, no signature cipher, and its
///   CDN URLs have no range/throttle cap, so AVPlayer streams them directly.
/// - Search: the **WEB_REMIX** (YouTube Music) client → real song results.
enum YouTube {

    static let visionUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    private static let visionVersion = "0.1"
    private static let remixVersion = "1.20260213.01.00"
    private static let webUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
    private static let musicPlayer = "https://music.youtube.com/youtubei/v1/player?prettyPrint=false"
    private static let musicSearch = "https://music.youtube.com/youtubei/v1/search?prettyPrint=false"
    private static let musicBrowse = "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false"
    /// YouTube Music "Songs" search filter.
    private static let songsFilter = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"

    private static var cachedVisitor: String?
    /// Resolved streams cached until near their expiry (lets us prefetch).
    private static var urlCache: [String: (url: URL, duration: Double, expires: Date)] = [:]

    // MARK: - Stream (VISIONOS, uncapped → direct streaming)

    /// Returns the playable URL and the REAL duration (seconds) from the format —
    /// AVPlayer misreads this fragmented MP4's own duration (~2×), so we carry the
    /// true value from `approxDurationMs`/`lengthSeconds`.
    static func streamURL(for videoId: String) async -> (url: URL, duration: Double)? {
        if let hit = urlCache[videoId], hit.expires > Date() { return (hit.url, hit.duration) }
        let visitor = await visitorData()
        var client: [String: Any] = [
            "clientName": "VISIONOS", "clientVersion": visionVersion,
            "deviceMake": "Apple", "deviceModel": "RealityDevice14,1",
            "osName": "visionOS", "osVersion": "1.3.21O771",
            "hl": "en", "gl": "US",
        ]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = [
            "context": ["client": client],
            "videoId": videoId,
            "contentCheckOk": true, "racyCheckOk": true,
        ]
        guard let json = await post(musicPlayer, name: "101", version: visionVersion,
                                    userAgent: visionUA, visitor: visitor, body: body),
              let streaming = json["streamingData"] as? [String: Any],
              let formats = streaming["adaptiveFormats"] as? [[String: Any]]
        else { return nil }

        // Best audio/mp4 (AAC) with a direct url — iOS can't play Opus/WebM.
        var best: [String: Any]?
        var bestRate = -1
        for f in formats {
            let mime = f["mimeType"] as? String ?? ""
            guard mime.hasPrefix("audio/mp4"), let u = f["url"] as? String, !u.isEmpty else { continue }
            let rate = (f["bitrate"] as? Int) ?? (f["averageBitrate"] as? Int) ?? 0
            if rate > bestRate { bestRate = rate; best = f }
        }
        guard let best, let u = best["url"] as? String, let url = URL(string: u) else { return nil }

        var dur = (Double(best["approxDurationMs"] as? String ?? "") ?? 0) / 1000
        if dur <= 0, let ls = (json["videoDetails"] as? [String: Any])?["lengthSeconds"] as? String {
            dur = Double(ls) ?? 0
        }
        urlCache[videoId] = (url, dur, Date().addingTimeInterval(4 * 3600))
        return (url, dur)
    }

    // MARK: - Search (WEB_REMIX music, on-device)

    static func search(_ query: String) async -> [Track] {
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": "en", "gl": "US"]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = [
            "context": ["client": client],
            "query": query,
            "params": songsFilter,
        ]
        guard let json = await post(musicSearch, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return [] }
        return parseMusicSearch(json)
    }

    private static func parseMusicSearch(_ json: [String: Any]) -> [Track] {
        guard
            let contents = json["contents"] as? [String: Any],
            let tabbed = contents["tabbedSearchResultsRenderer"] as? [String: Any],
            let tabs = tabbed["tabs"] as? [[String: Any]],
            let tabRenderer = tabs.first?["tabRenderer"] as? [String: Any],
            let content = tabRenderer["content"] as? [String: Any],
            let sectionList = content["sectionListRenderer"] as? [String: Any],
            let sections = sectionList["contents"] as? [[String: Any]]
        else { return [] }

        var out: [Track] = []
        for section in sections {
            guard
                let shelf = section["musicShelfRenderer"] as? [String: Any],
                let items = shelf["contents"] as? [[String: Any]]
            else { continue }
            for item in items {
                guard let r = item["musicResponsiveListItemRenderer"] as? [String: Any] else { continue }
                let videoId = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String
                    ?? overlayVideoId(r["overlay"])
                guard let vid = videoId, !vid.isEmpty else { continue }
                let cols = r["flexColumns"] as? [[String: Any]] ?? []
                out.append(Track(
                    videoId: vid,
                    title: flexText(cols, 0),
                    artist: flexArtist(cols),
                    thumbnail: musicThumb(r["thumbnail"]),
                    duration: 0   // filled from AVPlayer once the stream loads
                ))
                if out.count >= 25 { return out }
            }
        }
        return out
    }

    // MARK: - Home feed (WEB_REMIX browse FEmusic_home)

    /// The logged-out YouTube Music home: carousels of playlists/albums/songs.
    static func home() async -> [HomeSection] {
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": "en", "gl": "US"]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": "FEmusic_home"]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return [] }
        return parseHome(json)
    }

    private static func parseHome(_ json: [String: Any]) -> [HomeSection] {
        guard
            let contents = json["contents"] as? [String: Any],
            let browse = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
            let tabs = browse["tabs"] as? [[String: Any]],
            let tab = tabs.first?["tabRenderer"] as? [String: Any],
            let tabContent = tab["content"] as? [String: Any],
            let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
            let sections = sectionList["contents"] as? [[String: Any]]
        else { return [] }

        var out: [HomeSection] = []
        for section in sections {
            guard let shelf = section["musicCarouselShelfRenderer"] as? [String: Any] else { continue }
            let header = (shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
            let title = runsFirst(header?["title"])
            let items = (shelf["contents"] as? [[String: Any]] ?? []).compactMap(parseHomeItem)
            if !items.isEmpty { out.append(HomeSection(title: title, items: items)) }
        }
        return out
    }

    private static func parseHomeItem(_ item: [String: Any]) -> HomeItem? {
        // Playlist / album / artist card.
        if let r = item["musicTwoRowItemRenderer"] as? [String: Any] {
            let title = runsFirst(r["title"])
            guard !title.isEmpty else { return nil }
            let nav = r["navigationEndpoint"] as? [String: Any]
            let videoId = (nav?["watchEndpoint"] as? [String: Any])?["videoId"] as? String
            var browseId = (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
            if browseId == nil, let pid = (nav?["watchPlaylistEndpoint"] as? [String: Any])?["playlistId"] as? String {
                browseId = "VL" + pid
            }
            return HomeItem(
                title: title,
                subtitle: runsJoined(r["subtitle"]),
                thumbnail: musicThumb(r["thumbnailRenderer"]),
                videoId: videoId,
                browseId: browseId,
                isCircular: browseId?.hasPrefix("UC") ?? false,
            )
        }
        // A direct song (quick picks).
        if let r = item["musicResponsiveListItemRenderer"] as? [String: Any] {
            let vid = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String
                ?? overlayVideoId(r["overlay"])
            guard let v = vid, !v.isEmpty else { return nil }
            let cols = r["flexColumns"] as? [[String: Any]] ?? []
            return HomeItem(title: flexText(cols, 0), subtitle: flexArtist(cols),
                            thumbnail: musicThumb(r["thumbnail"]), videoId: v,
                            browseId: nil, isCircular: false)
        }
        return nil
    }

    // MARK: - Playlist / album tracks

    /// All songs inside a playlist or album (`browseId` from a home card).
    static func playlist(browseId: String) async -> [Track] {
        guard !browseId.isEmpty else { return [] }
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": "en", "gl": "US"]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": browseId]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return [] }

        var out: [Track] = []
        var seen = Set<String>()
        collectTracks(json, into: &out, seen: &seen)
        return out
    }

    /// Playlist/album responses vary in shape (single vs two column), so walk the
    /// whole tree and pull every song row, de-duping by videoId.
    private static func collectTracks(_ node: Any, into out: inout [Track], seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if let r = dict["musicResponsiveListItemRenderer"] as? [String: Any] {
                let vid = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String
                    ?? overlayVideoId(r["overlay"])
                if let v = vid, !v.isEmpty, seen.insert(v).inserted {
                    let cols = r["flexColumns"] as? [[String: Any]] ?? []
                    out.append(Track(videoId: v, title: flexText(cols, 0), artist: flexArtist(cols),
                                     thumbnail: musicThumb(r["thumbnail"]), duration: 0))
                }
                return
            }
            for (_, v) in dict { collectTracks(v, into: &out, seen: &seen) }
        } else if let arr = node as? [Any] {
            for v in arr { collectTracks(v, into: &out, seen: &seen) }
        }
    }

    // MARK: - Parsing helpers

    /// First run's text (or simpleText) of a `{runs:[…]}` / `{simpleText:…}` node.
    private static func runsFirst(_ obj: Any?) -> String {
        guard let o = obj as? [String: Any] else { return "" }
        if let runs = o["runs"] as? [[String: Any]], let f = runs.first?["text"] as? String { return f }
        return o["simpleText"] as? String ?? ""
    }

    /// All runs joined (e.g. "Album • 2024" or "Artist • 1.2M plays").
    private static func runsJoined(_ obj: Any?) -> String {
        guard let o = obj as? [String: Any], let runs = o["runs"] as? [[String: Any]] else {
            return runsFirst(obj)
        }
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    private static func flexText(_ cols: [[String: Any]], _ i: Int) -> String {
        guard cols.indices.contains(i),
              let r = cols[i]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = r["text"] as? [String: Any] else { return "" }
        if let runs = text["runs"] as? [[String: Any]], let f = runs.first?["text"] as? String { return f }
        return text["simpleText"] as? String ?? ""
    }

    /// The secondary line is "Artist • Album • m:ss"; take the first real segment.
    private static func flexArtist(_ cols: [[String: Any]]) -> String {
        guard cols.indices.contains(1),
              let r = cols[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = r["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]] else { return "" }
        for run in runs {
            let t = (run["text"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if !t.isEmpty && t != "•" { return t }
        }
        return ""
    }

    private static func overlayVideoId(_ overlay: Any?) -> String? {
        guard
            let o = overlay as? [String: Any],
            let mo = o["musicItemThumbnailOverlayRenderer"] as? [String: Any],
            let c = mo["content"] as? [String: Any],
            let btn = c["musicPlayButtonRenderer"] as? [String: Any],
            let nav = btn["playNavigationEndpoint"] as? [String: Any],
            let watch = nav["watchEndpoint"] as? [String: Any]
        else { return nil }
        return watch["videoId"] as? String
    }

    private static func musicThumb(_ obj: Any?) -> String {
        guard
            let mtr = (obj as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any],
            let t = mtr["thumbnail"] as? [String: Any],
            let thumbs = t["thumbnails"] as? [[String: Any]]
        else { return "" }
        let raw = thumbs.last?["url"] as? String ?? ""
        // YT Music art comes small (e.g. =w120-h120); request a crisp size.
        if let r = raw.range(of: "=w[0-9]+-h[0-9]+", options: .regularExpression) {
            return raw.replacingCharacters(in: r, with: "=w720-h720")
        }
        return raw
    }

    // MARK: - InnerTube POST

    private static func post(_ endpoint: String, name: String, version: String,
                             userAgent: String, visitor: String?, body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: endpoint),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = payload
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(name, forHTTPHeaderField: "X-Youtube-Client-Name")
        req.setValue(version, forHTTPHeaderField: "X-Youtube-Client-Version")
        req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        req.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        if let visitor { req.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id") }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    // MARK: - visitorData (music.youtube.com/sw.js_data)

    private static func visitorData() async -> String? {
        if let cachedVisitor { return cachedVisitor }
        guard let url = URL(string: "https://music.youtube.com/sw.js_data") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        guard let (data, _) = try? await URLSession.shared.data(for: req), data.count > 5 else { return nil }
        let jsonData = data.subdata(in: 5..<data.count)   // strip ")]}'\n"
        guard
            let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [Any],
            let a0 = arr.first as? [Any], a0.count > 2,
            let a2 = a0[2] as? [Any]
        else { return nil }
        for item in a2 {
            if let s = item as? String, s.count >= 3, s.hasPrefix("Cg") {
                let third = s[s.index(s.startIndex, offsetBy: 2)]
                if third == "t" || third == "s" { cachedVisitor = s; return s }
            }
        }
        return nil
    }
}
