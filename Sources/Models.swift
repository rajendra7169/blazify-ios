import Foundation

/// A playable song, as returned by the backend's /search and used throughout the app.
struct Track: Identifiable, Equatable, Codable, Hashable {
    let videoId: String
    let title: String
    let artist: String
    let thumbnail: String
    let duration: Double
    /// The artist's channel browseId (UC…), when the row carried one.
    let artistId: String?
    /// From the row's `MUSIC_EXPLICIT_BADGE`. Optional on purpose: `Track` is
    /// decoded from saved favourites, history and queues, and Swift's
    /// synthesised decoder throws on a missing key rather than using a default —
    /// a non-optional field here would wipe every existing install's library.
    var explicit: Bool?
    /// From `watchEndpointMusicConfig.musicVideoType`: ATV is the audio track,
    /// anything else is an actual music video.
    var video: Bool?
    /// A row's identity WITHIN a playlist. The same song can appear twice, so
    /// removing or moving one needs this rather than the video id.
    var setVideoId: String?

    var isExplicit: Bool { explicit ?? false }
    var isVideo: Bool { video ?? false }

    var id: String { videoId }
    var thumbnailURL: URL? { artURL(size: 0) }

    init(videoId: String, title: String, artist: String, thumbnail: String,
         duration: Double, artistId: String? = nil,
         explicit: Bool? = nil, video: Bool? = nil, setVideoId: String? = nil) {
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.thumbnail = thumbnail
        self.duration = duration
        self.artistId = artistId
        self.explicit = explicit
        self.video = video
        self.setVideoId = setVideoId
    }

    /// Thumbnail upscaled to a requested square size (googleusercontent resize).
    func artURL(size: Int) -> URL? {
        // A file:// path saved by an earlier install points into a container
        // that no longer exists — every reinstall gets a new one. Resolve the
        // download against the CURRENT container, and if it isn't downloaded
        // here, fall back to the thumbnail every video has.
        if thumbnail.hasPrefix("file:") {
            if let local = Downloads.shared.localArtURL(for: videoId) { return local }
            if let cached = AudioCache.shared.localArtURL(for: videoId) { return cached }
            return URL(string: Downloads.fallbackArt(videoId))
        }
        guard !thumbnail.isEmpty else {
            return videoId.isEmpty ? nil : URL(string: Downloads.fallbackArt(videoId))
        }
        guard size > 0 else { return URL(string: thumbnail) }

        // Catalogue URLs carry their size in the path: swap it.
        if let r = thumbnail.range(of: "=w[0-9]+-h[0-9]+", options: .regularExpression) {
            return URL(string: thumbnail.replacingCharacters(in: r, with: "=w\(size)-h\(size)"))
        }
        // Same host but no size yet — ask for one rather than taking whatever
        // small default the row happened to reference.
        if thumbnail.contains("googleusercontent.com"), !thumbnail.contains("=") {
            return URL(string: thumbnail + "=w\(size)-h\(size)")
        }
        // ytimg names its sizes instead: hqdefault is only 480×360, which is
        // why some songs looked soft while catalogue-hosted ones were sharp.
        // RemoteImage falls back if a video has no maxres.
        if thumbnail.contains("i.ytimg.com"),
           let r = thumbnail.range(of: "/(default|mqdefault|hqdefault|sddefault)\\.jpg",
                                   options: .regularExpression) {
            let name = size >= 700 ? "maxresdefault" : "sddefault"
            return URL(string: thumbnail.replacingCharacters(in: r, with: "/\(name).jpg"))
        }
        return URL(string: thumbnail)
    }

    /// Build from one /search JSON object.
    init?(json: [String: Any]) {
        guard let vid = json["videoId"] as? String, !vid.isEmpty else { return nil }
        videoId = vid
        title = json["title"] as? String ?? ""
        artist = json["artist"] as? String ?? ""
        thumbnail = json["thumbnail"] as? String ?? ""
        duration = (json["duration"] as? Double) ?? (json["duration"] as? NSNumber)?.doubleValue ?? 0
        artistId = json["artistId"] as? String
    }
}

extension Track {
    /// Show a played/liked song as a home-rail card.
    var asHomeItem: HomeItem {
        HomeItem(title: title, subtitle: artist, thumbnail: thumbnail,
                 videoId: videoId, browseId: nil, isCircular: false)
    }
}

/// One card in a home rail — either a song (plays directly) or a
/// playlist/album/artist (opens a detail list via `browseId`).
struct HomeItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let thumbnail: String
    let videoId: String?
    let browseId: String?
    let isCircular: Bool   // artists render as circles

    var thumbnailURL: URL? { URL(string: thumbnail) }
    var asTrack: Track {
        Track(videoId: videoId ?? "", title: title, artist: subtitle, thumbnail: thumbnail, duration: 0)
    }
}

/// One horizontal rail on the home feed (e.g. "New releases"). When `isSongs`,
/// the items are individual songs and render as the Quick Picks grid.
struct HomeSection: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let items: [HomeItem]
    let isSongs: Bool
}

/// A category chip under the greeting (All / Relax / Workout…). `params` re-browses
/// FEmusic_home filtered to that mood; nil = the default feed ("All").
struct HomeChip: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let params: String?
}

/// A Mood & Genres tile (colored, opens a page of playlists).
struct MoodItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let colorARGB: UInt
    let browseId: String?
    let params: String?
}

/// One of the user's own editable playlists.
struct UserPlaylist: Identifiable, Hashable {
    let id: String
    let title: String
    let thumbnail: String

    var thumbnailURL: URL? { URL(string: thumbnail) }
}

/// One shelf on an artist page — either a song list or a row of cards.
struct ArtistSection: Identifiable {
    let id = UUID()
    let title: String
    let songs: [Track]
    let cards: [HomeItem]
}

/// An artist channel page.
struct ArtistPage {
    let name: String
    let thumbnail: String
    let subscribers: String
    let sections: [ArtistSection]

    var thumbnailURL: URL? { URL(string: thumbnail) }
}

/// The whole home payload: filter chips + content sections.
struct HomeFeed {
    let chips: [HomeChip]
    var sections: [HomeSection]
    /// Token for the next page of shelves; nil once the feed is exhausted.
    var continuation: String?

    static let empty = HomeFeed(chips: [], sections: [], continuation: nil)
}
