import Foundation

/// Downloads a googlevideo audio URL in bounded Range chunks and returns the whole
/// file. These URLs serve only ~1 MiB per request (larger ranges 403), so we walk
/// the file in ≤1 MiB pieces — the same chunking Android's player does.
enum AudioDownloader {

    private static let chunk = 1_048_576   // 1 MiB — googlevideo's per-request cap

    /// Returns the full audio bytes, or nil on failure.
    static func download(_ url: URL, userAgent: String) async -> Data? {
        var data = Data()
        var total: Int?
        for _ in 0..<400 {   // hard cap (~400 MiB) so a bad response can't loop forever
            let offset = data.count
            let end = (total.map { min(offset + chunk, $0) } ?? (offset + chunk)) - 1
            var req = URLRequest(url: url)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
            guard
                let (part, resp) = try? await URLSession.shared.data(for: req),
                let http = resp as? HTTPURLResponse,
                http.statusCode == 200 || http.statusCode == 206
            else { return nil }
            data.append(part)
            if http.statusCode == 200 { return data }   // whole file at once
            if total == nil,
               let cr = http.value(forHTTPHeaderField: "Content-Range"),
               let tail = cr.split(separator: "/").last,
               let t = Int(tail) {
                total = t
            }
            if let total, data.count >= total { return data }
            if part.isEmpty { return data.isEmpty ? nil : data }
        }
        return nil
    }
}
