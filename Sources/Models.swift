import Foundation

/// A playable song, as returned by the backend's /search and used throughout the app.
struct Track: Identifiable, Equatable {
    let videoId: String
    let title: String
    let artist: String
    let thumbnail: String
    let duration: Double

    var id: String { videoId }
    var thumbnailURL: URL? { URL(string: thumbnail) }

    init(videoId: String, title: String, artist: String, thumbnail: String, duration: Double) {
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.thumbnail = thumbnail
        self.duration = duration
    }

    /// Build from one /search JSON object.
    init?(json: [String: Any]) {
        guard let vid = json["videoId"] as? String, !vid.isEmpty else { return nil }
        videoId = vid
        title = json["title"] as? String ?? ""
        artist = json["artist"] as? String ?? ""
        thumbnail = json["thumbnail"] as? String ?? ""
        duration = (json["duration"] as? Double) ?? (json["duration"] as? NSNumber)?.doubleValue ?? 0
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

/// The whole home payload: filter chips + content sections.
struct HomeFeed {
    let chips: [HomeChip]
    let sections: [HomeSection]

    static let empty = HomeFeed(chips: [], sections: [])
}
