import Foundation

/// Talks to the Blazify extractor server (Python + yt-dlp). The server does all the
/// YouTube extraction — the app just searches and plays the audio URL it serves.
enum BackendClient {

    static let base = "https://blazify-extractor-server.onrender.com"

    // MARK: - Search

    static func search(_ query: String) async -> [Track] {
        guard
            let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "\(base)/search?q=\(q)")
        else { return [] }
        guard
            let (data, _) = try? await URLSession.shared.data(from: url),
            let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { Track(json: $0) }
    }

    // MARK: - Playback

    /// The URL the app hands to AVPlayer — the server streams the audio with HTTP
    /// Range support, so playback and seeking work like any normal media URL.
    static func audioURL(for videoId: String) -> URL? {
        URL(string: "\(base)/audio?v=\(videoId)")
    }

    /// Ask the server to fetch/cache the song, polling until it's ready to stream so
    /// AVPlayer doesn't stall on the first (cold) download. Returns nil on success,
    /// or a short error message.
    static func prepare(_ videoId: String) async -> String? {
        guard let url = URL(string: "\(base)/prepare?v=\(videoId)") else { return "bad id" }
        for _ in 0..<75 {   // ~2.5 min ceiling
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if json["ready"] as? Bool == true { return nil }
                if let err = json["error"] as? String { return err }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return "timed out"
    }
}
