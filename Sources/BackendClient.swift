import Foundation

/// Search runs through the extractor server (its InnerTube search works fine from
/// the server). Playback is resolved on-device — see `YouTube` / `AudioDownloader`.
enum BackendClient {

    static let base = "https://blazify-extractor-server.onrender.com"

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
}
