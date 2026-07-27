import Foundation

/// Talks to the Blazify extractor backend.
enum BackendClient {
    static let base = "https://blazify-extractor-server.onrender.com"

    /// Search songs. Returns [] on any failure (keeps the UI simple).
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

    /// Resolve a videoId to a playable audio URL.
    static func streamURL(for videoId: String) async -> URL? {
        guard let url = URL(string: "\(base)/stream?v=\(videoId)") else { return nil }
        guard
            let (data, _) = try? await URLSession.shared.data(from: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let str = json["url"] as? String
        else { return nil }
        return URL(string: str)
    }
}
