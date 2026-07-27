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
