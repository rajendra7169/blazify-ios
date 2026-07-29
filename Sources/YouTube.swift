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
    private static let musicSuggest = "https://music.youtube.com/youtubei/v1/music/get_search_suggestions?prettyPrint=false"
    private static let musicAccount = "https://music.youtube.com/youtubei/v1/account/account_menu?prettyPrint=false"
    /// YouTube Music "Songs" search filter.
    private static let songsFilter = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"

    private static var cachedVisitor: String?
    /// Resolved streams cached until near their expiry (lets us prefetch).
    private static var urlCache: [String: (url: URL, duration: Double, expires: Date)] = [:]
    /// Concurrent downloads and the player's prefetch all touch the cache —
    /// unlocked access was a data race that silently killed download tasks.
    private static let urlCacheLock = NSLock()

    // MARK: - Stream (VISIONOS, uncapped → direct streaming)

    /// Returns the playable URL and the REAL duration (seconds) from the format —
    /// AVPlayer misreads this fragmented MP4's own duration (~2×), so we carry the
    /// true value from `approxDurationMs`/`lengthSeconds`.
    /// Per-song loudness from `playerConfig.audioConfig.loudnessDb`, kept beside
    /// the URL cache so volume normalisation needs no extra request.
    private static var loudnessCache: [String: Double] = [:]
    private static let loudnessLock = NSLock()

    static func loudnessDb(for videoId: String) -> Double? {
        loudnessLock.lock()
        defer { loudnessLock.unlock() }
        return loudnessCache[videoId]
    }

    static func streamURL(for videoId: String) async -> (url: URL, duration: Double)? {
        urlCacheLock.lock()
        let hit = urlCache[videoId]
        urlCacheLock.unlock()
        if let hit, hit.expires > Date() { return (hit.url, hit.duration) }

        let visitor = await visitorData()
        // Settings → Stream sources: walk the chosen order until one client
        // answers. Any single client can start being refused; the chain is what
        // keeps playback working when that happens.
        let clients = await MainActor.run { StreamPrefs.shared.order }
        // Highest bitrate, lowest, or whatever the connection can carry.
        let wantsLowest = await MainActor.run {
            let quality = PlaybackPrefs.shared.quality
            return quality == .low
                || (quality == .auto && !Reachability.shared.isUnmetered)
        }

        for client in clients {
            guard let picked = await resolve(videoId, with: client, visitor: visitor,
                                             wantsLowest: wantsLowest) else { continue }
            urlCacheLock.lock()
            urlCache[videoId] = (picked.url, picked.duration, Date().addingTimeInterval(4 * 3600))
            urlCacheLock.unlock()
            return (picked.url, picked.duration)
        }
        return nil
    }

    /// One client's attempt at a playable audio URL.
    private static func resolve(_ videoId: String, with client: StreamClient,
                                visitor: String?,
                                wantsLowest: Bool) async -> (url: URL, duration: Double)? {
        var context = client.context
        if let visitor { context["visitorData"] = visitor }
        let body: [String: Any] = [
            "context": ["client": context],
            "videoId": videoId,
            "contentCheckOk": true, "racyCheckOk": true,
        ]
        guard let json = await post(musicPlayer, name: client.number, version: client.version,
                                    userAgent: client.userAgent, visitor: visitor, body: body),
              (json["playabilityStatus"] as? [String: Any])?["status"] as? String == "OK",
              let streaming = json["streamingData"] as? [String: Any],
              let formats = streaming["adaptiveFormats"] as? [[String: Any]]
        else { return nil }

        // Track loudness for volume normalisation. In testing only ANDROID_VR
        // reports it, so this quietly stays empty on the other clients.
        if let config = json["playerConfig"] as? [String: Any],
           let audio = config["audioConfig"] as? [String: Any],
           let db = audio["loudnessDb"] as? Double {
            loudnessLock.lock()
            loudnessCache[videoId] = db
            loudnessLock.unlock()
        }

        // Audio/mp4 (AAC) with a direct url — iOS can't play Opus/WebM.
        var best: [String: Any]?
        var bestRate = wantsLowest ? Int.max : -1
        for f in formats {
            let mime = f["mimeType"] as? String ?? ""
            guard mime.hasPrefix("audio/mp4"), let u = f["url"] as? String, !u.isEmpty else { continue }
            let rate = (f["bitrate"] as? Int) ?? (f["averageBitrate"] as? Int) ?? 0
            if wantsLowest ? (rate < bestRate) : (rate > bestRate) { bestRate = rate; best = f }
        }
        guard let best, let u = best["url"] as? String, let url = URL(string: u) else { return nil }

        var dur = (Double(best["approxDurationMs"] as? String ?? "") ?? 0) / 1000
        if dur <= 0, let ls = (json["videoDetails"] as? [String: Any])?["lengthSeconds"] as? String {
            dur = Double(ls) ?? 0
        }
        return (url, dur)
    }

    // MARK: - Search (WEB_REMIX music, on-device)

    static func search(_ query: String) async -> [Track] {
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
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

    /// Live search suggestions, as Android's `searchSuggestions()` does.
    /// Section 0 is the completed query strings, section 1 is real songs — so
    /// we can put playable results above text suggestions while you type.
    static func searchSuggestions(_ query: String) async -> (queries: [String], songs: [Track]) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ([], []) }

        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "input": q]

        guard let json = await post(musicSuggest, name: "67",
                                    version: remixVersion, userAgent: webUA,
                                    visitor: visitor, body: body),
              let sections = json["contents"] as? [[String: Any]]
        else { return ([], []) }

        var queries: [String] = []
        var songs: [Track] = []
        var seen = Set<String>()

        for section in sections {
            guard let contents = (section["searchSuggestionsSectionRenderer"] as? [String: Any])?["contents"]
                    as? [[String: Any]] else { continue }
            for item in contents {
                if let renderer = item["searchSuggestionRenderer"] as? [String: Any] {
                    let text = runsJoined(renderer["suggestion"])
                    if !text.isEmpty { queries.append(text) }
                } else if item["musicResponsiveListItemRenderer"] != nil {
                    collectTracks(item, into: &songs, seen: &seen)
                }
            }
        }
        return (queries, songs)
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
                    duration: 0,   // filled from AVPlayer once the stream loads
                    artistId: flexArtistId(cols)
                ))
                if out.count >= 25 { return out }
            }
        }
        return out
    }

    // MARK: - Home feed (WEB_REMIX browse FEmusic_home)

    /// The YouTube Music home: filter chips + carousels (personalized when signed in).
    /// `params` re-browses filtered to a chip's mood.
    /// The home feed. Pass `continuation` to fetch the next page of shelves —
    /// that token is session-bound, so the cached `visitorData` must be sent
    /// with it or YouTube answers with an empty page.
    static func home(params: String? = nil, continuation: String? = nil) async -> HomeFeed {
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }

        var body: [String: Any] = ["context": ["client": client]]
        if let continuation {
            body["continuation"] = continuation
        } else {
            body["browseId"] = "FEmusic_home"
            if let params { body["params"] = params }
        }

        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body, login: true)
        else { return .empty }
        return continuation == nil ? parseHome(json) : parseHomeContinuation(json)
    }

    /// Continuation pages arrive under `continuationContents.sectionListContinuation`
    /// rather than the tabbed browse shape.
    private static func parseHomeContinuation(_ json: [String: Any]) -> HomeFeed {
        guard let cc = json["continuationContents"] as? [String: Any],
              let list = cc["sectionListContinuation"] as? [String: Any]
        else { return .empty }
        let sections = parseShelves(list["contents"] as? [[String: Any]] ?? [])
        return HomeFeed(chips: [], sections: sections,
                        continuation: nextContinuation(list))
    }

    /// The `continuations[].nextContinuationData.continuation` token, if present.
    private static func nextContinuation(_ node: [String: Any]) -> String? {
        guard let list = node["continuations"] as? [[String: Any]] else { return nil }
        for entry in list {
            if let next = (entry["nextContinuationData"] as? [String: Any])?["continuation"] as? String {
                return next
            }
        }
        return nil
    }

    private static func parseShelves(_ sections: [[String: Any]]) -> [HomeSection] {
        var out: [HomeSection] = []
        for section in sections {
            guard let shelf = section["musicCarouselShelfRenderer"] as? [String: Any] else { continue }
            let header = (shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
            let title = runsFirst(header?["title"])
            let contentsArr = shelf["contents"] as? [[String: Any]] ?? []
            let isSongs = contentsArr.first?["musicResponsiveListItemRenderer"] != nil
            let items = contentsArr.compactMap(parseHomeItem)
            if !items.isEmpty { out.append(HomeSection(title: title, items: items, isSongs: isSongs)) }
        }
        return out
    }

    private static func parseHome(_ json: [String: Any]) -> HomeFeed {
        guard
            let contents = json["contents"] as? [String: Any],
            let browse = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
            let tabs = browse["tabs"] as? [[String: Any]],
            let tab = tabs.first?["tabRenderer"] as? [String: Any],
            let tabContent = tab["content"] as? [String: Any],
            let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
            let sections = sectionList["contents"] as? [[String: Any]]
        else { return .empty }

        return HomeFeed(chips: parseChips(sectionList),
                        sections: parseShelves(sections),
                        continuation: nextContinuation(sectionList))
    }

    private static func parseChips(_ sectionList: [String: Any]) -> [HomeChip] {
        guard let header = sectionList["header"] as? [String: Any],
              let cloud = header["chipCloudRenderer"] as? [String: Any],
              let chips = cloud["chips"] as? [[String: Any]] else { return [] }
        var out: [HomeChip] = [HomeChip(title: "All", params: nil)]
        for c in chips {
            guard let cr = c["chipCloudChipRenderer"] as? [String: Any] else { continue }
            let title = runsFirst(cr["text"])
            let params = ((cr["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["params"] as? String
            if !title.isEmpty { out.append(HomeChip(title: title, params: params)) }
        }
        return out
    }

    // MARK: - Lyrics (YouTube's own, via next -> MPLY browse)

    /// Plain lyrics YouTube Music carries for a track, plus the upstream source
    /// name it credits in the footer (usually Musixmatch). No login needed.
    static func lyrics(videoId: String) async -> (text: String, source: String)? {
        guard !videoId.isEmpty else { return nil }
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }

        // The lyrics tab hangs off `next` as a browseId beginning MPLY.
        let nextURL = "https://music.youtube.com/youtubei/v1/next?prettyPrint=false"
        guard let nextJSON = await post(nextURL, name: "67", version: remixVersion,
                                        userAgent: webUA, visitor: visitor,
                                        body: ["context": ["client": client], "videoId": videoId])
        else { return nil }
        guard let browseId = findLyricsBrowseId(nextJSON) else { return nil }

        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor,
                                    body: ["context": ["client": client], "browseId": browseId]),
              let contents = json["contents"] as? [String: Any],
              let list = contents["sectionListRenderer"] as? [String: Any],
              let sections = list["contents"] as? [[String: Any]],
              let shelf = sections.first?["musicDescriptionShelfRenderer"] as? [String: Any]
        else { return nil }

        let text = runsJoined(shelf["description"])
        guard !text.isEmpty else { return nil }
        // Footer reads "Source: Musixmatch".
        let footer = runsJoined(shelf["footer"])
        let source = footer.replacingOccurrences(of: "Source: ", with: "")
        return (text, source.isEmpty ? "YouTube Music" : source)
    }

    private static func findLyricsBrowseId(_ node: Any) -> String? {
        findBrowseId(node, prefix: "MPLY")
    }

    /// First `browseId` under this node with the given prefix — the tabs hanging
    /// off `next` are identified that way (MPLY = lyrics, MPTR = related).
    private static func findBrowseId(_ node: Any, prefix: String) -> String? {
        if let dict = node as? [String: Any] {
            if let id = dict["browseId"] as? String, id.hasPrefix(prefix) { return id }
            for (_, v) in dict {
                if let found = findBrowseId(v, prefix: prefix) { return found }
            }
        } else if let arr = node as? [Any] {
            for v in arr {
                if let found = findBrowseId(v, prefix: prefix) { return found }
            }
        }
        return nil
    }

    // MARK: - Related (what powers the ever-changing home rails)

    /// The "Related" tab for a song: "You might also like", other performances,
    /// similar artists and so on. Android seeds Daily Discover and "Similar to X"
    /// from this, which is why its home feed differs on every refresh.
    static func related(videoId: String) async -> [HomeSection] {
        guard !videoId.isEmpty else { return [] }
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }

        let nextURL = "https://music.youtube.com/youtubei/v1/next?prettyPrint=false"
        guard let nextJSON = await post(nextURL, name: "67", version: remixVersion,
                                        userAgent: webUA, visitor: visitor,
                                        body: ["context": ["client": client], "videoId": videoId]),
              let browseId = findBrowseId(nextJSON, prefix: "MPTR")
        else { return [] }

        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor,
                                    body: ["context": ["client": client], "browseId": browseId])
        else { return [] }

        var out: [HomeSection] = []
        collectShelves(json, into: &out)
        return out
    }

    /// Every carousel shelf anywhere under this node, in order.
    private static func collectShelves(_ node: Any, into out: inout [HomeSection]) {
        if let dict = node as? [String: Any] {
            if let shelf = dict["musicCarouselShelfRenderer"] as? [String: Any] {
                let header = (shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
                let contentsArr = shelf["contents"] as? [[String: Any]] ?? []
                let isSongs = contentsArr.first?["musicResponsiveListItemRenderer"] != nil
                let items = contentsArr.compactMap(parseHomeItem)
                if !items.isEmpty {
                    out.append(HomeSection(title: runsFirst(header?["title"]),
                                           items: items, isSongs: isSongs))
                }
                return
            }
            for (_, v) in dict { collectShelves(v, into: &out) }
        } else if let arr = node as? [Any] {
            for v in arr { collectShelves(v, into: &out) }
        }
    }

    // MARK: - Artist

    /// Artists-only search filter.
    private static let artistsFilter = "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
    private static var artistIdCache: [String: String] = [:]

    /// Resolve an artist's channel id from their name — the fallback for rows
    /// that carry no browseId (mirrors Android's resolveArtistIdMap).
    static func resolveArtistId(name: String) async -> String? {
        let key = name.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        if let hit = artistIdCache[key] { return hit }

        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = [
            "context": ["client": client],
            "query": key,
            "params": artistsFilter,
        ]
        guard let json = await post(musicSearch, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return nil }

        var found: String?
        collectFirstArtist(json, name: key, into: &found)
        if let found { artistIdCache[key] = found }
        return found
    }

    private static func collectFirstArtist(_ node: Any, name: String, into found: inout String?) {
        guard found == nil else { return }
        if let dict = node as? [String: Any] {
            if let r = dict["musicResponsiveListItemRenderer"] as? [String: Any] {
                let nav = r["navigationEndpoint"] as? [String: Any]
                if let id = (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String,
                   id.hasPrefix("UC") {
                    let cols = r["flexColumns"] as? [[String: Any]] ?? []
                    let title = flexText(cols, 0)
                    // Prefer an exact name match, as Android does.
                    if title.compare(name, options: .caseInsensitive) == .orderedSame {
                        found = id
                    } else if found == nil {
                        found = id
                    }
                }
                return
            }
            for (_, v) in dict { collectFirstArtist(v, name: name, into: &found) }
        } else if let arr = node as? [Any] {
            for v in arr { collectFirstArtist(v, name: name, into: &found) }
        }
    }

    /// An artist channel page: header + the shelves below it.
    static func artist(browseId: String) async -> ArtistPage? {
        guard browseId.hasPrefix("UC") else { return nil }
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": browseId]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body, login: true)
        else { return nil }

        let header = json["header"] as? [String: Any]
        let immersive = header?["musicImmersiveHeaderRenderer"] as? [String: Any]
        let visual = header?["musicVisualHeaderRenderer"] as? [String: Any]
        let plain = header?["musicHeaderRenderer"] as? [String: Any]

        let name = [immersive, visual, plain].compactMap { $0 }
            .map { runsFirst($0["title"]) }.first(where: { !$0.isEmpty }) ?? ""
        guard !name.isEmpty else { return nil }

        var thumb = musicThumb(immersive?["thumbnail"])
        if thumb.isEmpty { thumb = musicThumb(visual?["foregroundThumbnail"]) }

        // Subscriber count lives in one of three renderers depending on the variant.
        var subscribers = ""
        if let btn = (immersive?["subscriptionButton2"] as? [String: Any])?["subscribeButtonRenderer"] as? [String: Any] {
            subscribers = runsFirst(btn["subscriberCountWithSubscribeText"])
        }
        if subscribers.isEmpty,
           let btn = (immersive?["subscriptionButton"] as? [String: Any])?["subscribeButtonRenderer"] as? [String: Any] {
            subscribers = runsFirst(btn["longSubscriberCountText"])
            if subscribers.isEmpty { subscribers = runsFirst(btn["shortSubscriberCountText"]) }
        }

        // Shelves: musicShelfRenderer = song list, musicCarouselShelfRenderer = cards.
        var sections: [ArtistSection] = []
        if let contents = json["contents"] as? [String: Any],
           let browse = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = browse["tabs"] as? [[String: Any]],
           let tab = tabs.first?["tabRenderer"] as? [String: Any],
           let tabContent = tab["content"] as? [String: Any],
           let list = tabContent["sectionListRenderer"] as? [String: Any],
           let items = list["contents"] as? [[String: Any]] {
            for section in items {
                if let shelf = section["musicShelfRenderer"] as? [String: Any] {
                    var tracks: [Track] = []
                    var seen = Set<String>()
                    collectTracks(shelf, into: &tracks, seen: &seen)
                    if !tracks.isEmpty {
                        sections.append(ArtistSection(title: runsFirst(shelf["title"]),
                                                      songs: tracks, cards: []))
                    }
                } else if let shelf = section["musicCarouselShelfRenderer"] as? [String: Any] {
                    let head = (shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
                    let cards = (shelf["contents"] as? [[String: Any]] ?? []).compactMap(parseHomeItem)
                    if !cards.isEmpty {
                        sections.append(ArtistSection(title: runsFirst(head?["title"]),
                                                      songs: [], cards: cards))
                    }
                }
            }
        }

        return ArtistPage(name: name, thumbnail: thumb, subscribers: subscribers, sections: sections)
    }

    // MARK: - Moods & genres

    /// The "Moods & moments" / "Genres" tiles from FEmusic_moods_and_genres.
    static func moods() async -> [MoodItem] {
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": "FEmusic_moods_and_genres"]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return [] }
        guard
            let contents = json["contents"] as? [String: Any],
            let browse = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
            let tabs = browse["tabs"] as? [[String: Any]],
            let tab = tabs.first?["tabRenderer"] as? [String: Any],
            let tabContent = tab["content"] as? [String: Any],
            let sectionList = tabContent["sectionListRenderer"] as? [String: Any],
            let sections = sectionList["contents"] as? [[String: Any]]
        else { return [] }

        var out: [MoodItem] = []
        for section in sections {
            let items = (section["gridRenderer"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
            for item in items {
                guard let b = item["musicNavigationButtonRenderer"] as? [String: Any] else { continue }
                let title = runsFirst(b["buttonText"])
                guard !title.isEmpty else { continue }
                let color = ((b["solid"] as? [String: Any])?["leftStripeColor"] as? NSNumber)?.uintValue ?? 0xFF29_2929
                let click = (b["clickCommand"] as? [String: Any])?["browseEndpoint"] as? [String: Any]
                out.append(MoodItem(title: title, colorARGB: color,
                                    browseId: click?["browseId"] as? String,
                                    params: click?["params"] as? String))
            }
        }
        return out
    }

    /// Playlists inside a mood/genre category.
    static func moodPlaylists(browseId: String, params: String?) async -> [HomeItem] {
        guard !browseId.isEmpty else { return [] }
        let visitor = await visitorData()
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        var body: [String: Any] = ["context": ["client": client], "browseId": browseId]
        if let params { body["params"] = params }
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body)
        else { return [] }
        var out: [HomeItem] = []
        var seen = Set<String>()
        collectCards(json, into: &out, seen: &seen)
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
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": browseId]
        // Signed in: the user's own playlists are private, so an unauthenticated
        // browse comes back as an empty shell ("Nothing to play here").
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body, login: true)
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
                                     thumbnail: musicThumb(r["thumbnail"]), duration: 0,
                                     artistId: flexArtistId(cols)))
                }
                return
            }
            for (_, v) in dict { collectTracks(v, into: &out, seen: &seen) }
        } else if let arr = node as? [Any] {
            for v in arr { collectTracks(v, into: &out, seen: &seen) }
        }
    }

    // MARK: - Listening history (server side)

    /// One dated group of the account's YouTube Music history.
    struct HistorySection: Identifiable {
        var id: String { title }
        let title: String    // "Today", "Yesterday", "This week", … — YouTube's own labels
        let tracks: [Track]
    }

    /// The account's own play history, already grouped by date by YouTube.
    /// Mirrors Android's `musicHistory()` browse of `FEmusic_history`.
    static func musicHistory() async -> [HistorySection] {
        guard Auth.shared.isLoggedIn else { return [] }
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": "FEmusic_history"]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body, login: true)
        else { return [] }

        var out: [HistorySection] = []
        var seen = Set<String>()
        collectHistory(json, into: &out, seen: &seen)
        return out.filter { !$0.tracks.isEmpty }
    }

    /// Each dated group arrives as its own `musicShelfRenderer` with a title.
    private static func collectHistory(_ node: Any, into out: inout [HistorySection],
                                       seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if let shelf = dict["musicShelfRenderer"] as? [String: Any] {
                let title = runsJoined(shelf["title"])
                var tracks: [Track] = []
                // Deduping is per shelf, so the same song can legitimately show
                // up under both Today and Yesterday.
                var shelfSeen = Set<String>()
                collectTracks(shelf["contents"] as Any, into: &tracks, seen: &shelfSeen)
                if !title.isEmpty, !tracks.isEmpty, seen.insert(title).inserted {
                    out.append(HistorySection(title: title, tracks: tracks))
                }
                return
            }
            for (_, v) in dict { collectHistory(v, into: &out, seen: &seen) }
        } else if let arr = node as? [Any] {
            for v in arr { collectHistory(v, into: &out, seen: &seen) }
        }
    }

    // MARK: - Account (login validation)

    struct AccountInfo {
        let name: String
        let email: String?
    }

    /// Signed-in account details via account_menu — also the login-validity check.
    static func accountInfo() async -> AccountInfo? {
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client]]
        guard let json = await post(musicAccount, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body, login: true)
        else { return nil }

        guard
            let actions = json["actions"] as? [[String: Any]],
            let popup = (actions.first?["openPopupAction"] as? [String: Any])?["popup"] as? [String: Any],
            let menu = popup["multiPageMenuRenderer"] as? [String: Any],
            let header = menu["header"] as? [String: Any],
            let account = header["activeAccountHeaderRenderer"] as? [String: Any]
        else { return nil }

        let name = runsFirst(account["accountName"])
        guard !name.isEmpty else { return nil }
        let email = runsFirst(account["email"])
        return AccountInfo(name: name, email: email.isEmpty ? nil : email)
    }

    // MARK: - Like / library writes (signed-in)

    /// Like or un-like a song in the user's YouTube Music library.
    /// (InnerTube `like/like` + `like/removelike`, the same calls the web app makes.)
    @discardableResult
    static func rateSong(videoId: String, like: Bool) async -> Bool {
        guard Auth.shared.isLoggedIn, !videoId.isEmpty else { return false }
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = [
            "context": ["client": client],
            "target": ["videoId": videoId],
        ]
        let endpoint = "https://music.youtube.com/youtubei/v1/like/"
            + (like ? "like" : "removelike") + "?prettyPrint=false"
        let json = await post(endpoint, name: "67", version: remixVersion,
                              userAgent: webUA, visitor: visitor, body: body, login: true)
        // A successful call echoes a responseContext; errors carry an "error" object.
        guard let json else { return false }
        return json["error"] == nil
    }

    /// The user's Liked songs (the "LM" auto-playlist).
    static func likedSongs() async -> [Track] {
        guard Auth.shared.isLoggedIn else { return [] }
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": "FEmusic_liked_videos"]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body, login: true)
        else { return [] }
        var out: [Track] = []
        var seen = Set<String>()
        collectTracks(json, into: &out, seen: &seen)
        return out
    }

    // MARK: - Playlist writes (signed-in)

    /// The user's own editable playlists (the ones an EDIT menu item marks).
    static func editablePlaylists() async -> [UserPlaylist] {
        guard Auth.shared.isLoggedIn else { return [] }
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": "FEmusic_liked_playlists"]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body, login: true)
        else { return [] }

        var out: [UserPlaylist] = []
        var seen = Set<String>()
        collectEditablePlaylists(json, into: &out, seen: &seen)
        return out
    }

    private static func collectEditablePlaylists(_ node: Any, into out: inout [UserPlaylist],
                                                 seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if let r = dict["musicTwoRowItemRenderer"] as? [String: Any] {
                let nav = r["navigationEndpoint"] as? [String: Any]
                let raw = (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String ?? ""
                let id = raw.hasPrefix("VL") ? String(raw.dropFirst(2)) : raw
                // Only playlists the user can edit carry an EDIT menu entry.
                let editable = menuHasIcon(r["menu"], "EDIT")
                if editable, !id.isEmpty, id != "LM", id != "SE", seen.insert(id).inserted {
                    out.append(UserPlaylist(id: id, title: runsFirst(r["title"]),
                                            thumbnail: musicThumb(r["thumbnailRenderer"])))
                }
                return
            }
            for (_, v) in dict { collectEditablePlaylists(v, into: &out, seen: &seen) }
        } else if let arr = node as? [Any] {
            for v in arr { collectEditablePlaylists(v, into: &out, seen: &seen) }
        }
    }

    private static func menuHasIcon(_ menu: Any?, _ iconType: String) -> Bool {
        guard let m = (menu as? [String: Any])?["menuRenderer"] as? [String: Any],
              let items = m["items"] as? [[String: Any]] else { return false }
        for item in items {
            guard let nav = item["menuNavigationItemRenderer"] as? [String: Any],
                  let icon = nav["icon"] as? [String: Any] else { continue }
            if icon["iconType"] as? String == iconType { return true }
        }
        return false
    }

    /// Create a private playlist; returns its new playlistId.
    static func createPlaylist(title: String) async -> String? {
        guard Auth.shared.isLoggedIn, !title.isEmpty else { return nil }
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = [
            "context": ["client": client],
            "title": title,
            "privacyStatus": "PRIVATE",
        ]
        let endpoint = "https://music.youtube.com/youtubei/v1/playlist/create?prettyPrint=false"
        guard let json = await post(endpoint, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body, login: true)
        else { return nil }
        return json["playlistId"] as? String
    }

    /// Add a song to a playlist (browse/edit_playlist, ACTION_ADD_VIDEO).
    @discardableResult
    static func addToPlaylist(playlistId: String, videoId: String) async -> Bool {
        guard Auth.shared.isLoggedIn, !playlistId.isEmpty, !videoId.isEmpty else { return false }
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let id = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId
        let body: [String: Any] = [
            "context": ["client": client],
            "playlistId": id,
            "actions": [["action": "ACTION_ADD_VIDEO", "addedVideoId": videoId]],
        ]
        let endpoint = "https://music.youtube.com/youtubei/v1/browse/edit_playlist?prettyPrint=false"
        guard let json = await post(endpoint, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body, login: true)
        else { return false }
        if let status = json["status"] as? String { return status == "STATUS_SUCCEEDED" }
        return json["error"] == nil
    }

    // MARK: - Library (signed-in)

    /// The user's saved/created playlists (FEmusic_liked_playlists grid).
    static func libraryPlaylists() async -> [HomeItem] {
        await library("FEmusic_liked_playlists")
    }

    /// The user's own uploads (FEmusic_library_privately_owned_tracks).
    static func uploadedSongs() async -> [Track] {
        guard Auth.shared.isLoggedIn else { return [] }
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client],
                                   "browseId": "FEmusic_library_privately_owned_tracks"]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body, login: true)
        else { return [] }
        var out: [Track] = []
        var seen = Set<String>()
        collectTracks(json, into: &out, seen: &seen)
        return out
    }

    /// Any library shelf: liked playlists / albums / subscribed artists.
    static func library(_ browseId: String) async -> [HomeItem] {
        guard Auth.shared.isLoggedIn else { return [] }
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client], "browseId": browseId]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body, login: true)
        else { return [] }

        var out: [HomeItem] = []
        var seen = Set<String>()
        collectCards(json, into: &out, seen: &seen)
        return out
    }

    /// Walk the tree for playlist/album/artist cards (used by the library grids).
    private static func collectCards(_ node: Any, into out: inout [HomeItem], seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if dict["musicTwoRowItemRenderer"] != nil, let item = parseHomeItem(dict),
               let bid = item.browseId, seen.insert(bid).inserted {
                out.append(item)
                return
            }
            // Artists (and chart rows) come back as list items, not two-row
            // cards — without this the library artist pages parse as empty.
            if let r = dict["musicResponsiveListItemRenderer"] as? [String: Any],
               let item = parseListCard(r), let bid = item.browseId,
               seen.insert(bid).inserted {
                out.append(item)
                return
            }
            for (_, v) in dict { collectCards(v, into: &out, seen: &seen) }
        } else if let arr = node as? [Any] {
            for v in arr { collectCards(v, into: &out, seen: &seen) }
        }
    }

    /// A list-shaped card: name in the first column, "N subscribers" in the
    /// second, and the destination on the row's own navigation endpoint.
    private static func parseListCard(_ r: [String: Any]) -> HomeItem? {
        let nav = r["navigationEndpoint"] as? [String: Any]
        guard let browseId = (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String,
              !browseId.isEmpty else { return nil }
        let cols = r["flexColumns"] as? [[String: Any]] ?? []
        let title = flexText(cols, 0)
        guard !title.isEmpty else { return nil }
        return HomeItem(title: title, subtitle: flexText(cols, 1),
                        thumbnail: musicThumb(r["thumbnail"]), videoId: nil,
                        browseId: browseId,
                        isCircular: browseId.hasPrefix("UC"))
    }

    // MARK: - Charts (what's trending on YouTube Music)

    /// The global/region charts page: trending videos plus the top artists.
    /// Mirrors Android's `getChartsPage()` browse of `FEmusic_charts`.
    static func charts() async -> (songs: [Track], artists: [HomeItem]) {
        var visitor = Auth.shared.visitorData
        if visitor == nil { visitor = await visitorData() }
        var client: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": remixVersion,
                                     "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        if let visitor { client["visitorData"] = visitor }
        let body: [String: Any] = ["context": ["client": client],
                                   "browseId": "FEmusic_charts",
                                   "params": "ggMGCgQIgAQ%3D"]
        guard let json = await post(musicBrowse, name: "67", version: remixVersion,
                                    userAgent: webUA, visitor: visitor, body: body,
                                    login: Auth.shared.isLoggedIn)
        else { return ([], []) }

        // Top-songs shelves are list rows; the video charts are two-row cards.
        var songs: [Track] = []
        var songSeen = Set<String>()
        collectTracks(json, into: &songs, seen: &songSeen)
        collectChartVideos(json, into: &songs, seen: &songSeen)

        var cards: [HomeItem] = []
        var cardSeen = Set<String>()
        collectCards(json, into: &cards, seen: &cardSeen)
        let artists = cards.filter { $0.browseId?.hasPrefix("UC") == true }

        // Signed out, the charts page returns ~40 artists but only a couple of
        // songs, which left the Trending rail looking artist-only. Top up from
        // the home feed's own trending shelves (Today's hits, Fresh tunes…).
        if songs.count < 6 {
            let feed = await home()
            for item in feed.sections.flatMap(\.items) {
                guard let vid = item.videoId, !vid.isEmpty, songSeen.insert(vid).inserted else { continue }
                songs.append(item.asTrack)
                if songs.count >= 12 { break }
            }
        }

        return (songs, artists)
    }

    /// Two-row chart cards that point at a video rather than a browse page.
    private static func collectChartVideos(_ node: Any, into out: inout [Track],
                                           seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if dict["musicTwoRowItemRenderer"] != nil, let item = parseHomeItem(dict),
               let vid = item.videoId, !vid.isEmpty, seen.insert(vid).inserted {
                out.append(item.asTrack)
                return
            }
            for (_, v) in dict { collectChartVideos(v, into: &out, seen: &seen) }
        } else if let arr = node as? [Any] {
            for v in arr { collectChartVideos(v, into: &out, seen: &seen) }
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

    /// The artist's channel id from the secondary line's runs (UC…).
    private static func flexArtistId(_ cols: [[String: Any]]) -> String? {
        guard cols.indices.contains(1),
              let r = cols[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = r["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]] else { return nil }
        for run in runs {
            if let nav = run["navigationEndpoint"] as? [String: Any],
               let browse = nav["browseEndpoint"] as? [String: Any],
               let id = browse["browseId"] as? String, id.hasPrefix("UC") {
                return id
            }
        }
        return nil
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
        // A middling canonical size: `RemoteImage` rewrites this per use, and
        // anything that doesn't pass a size gets something sane rather than the
        // 720² we used to request for every 48pt row.
        if let r = raw.range(of: "=w[0-9]+-h[0-9]+", options: .regularExpression) {
            return raw.replacingCharacters(in: r, with: "=w544-h544")
        }
        return raw
    }

    // MARK: - InnerTube POST

    private static func post(_ endpoint: String, name: String, version: String,
                             userAgent: String, visitor: String?, body: [String: Any],
                             login: Bool = false) async -> [String: Any]? {
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
        // Signed-in requests (library, personalized home) carry the cookie + SAPISIDHASH.
        if login {
            for (key, value) in Auth.shared.headers() { req.setValue(value, forHTTPHeaderField: key) }
        }
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
