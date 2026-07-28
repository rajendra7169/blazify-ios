import Foundation
import Combine

/// Songs you've played, kept on disk automatically — the equivalent of
/// ExoPlayer's SimpleCache on Android.
///
/// AVPlayer doesn't persist progressive streams itself, so we fetch the same
/// resolved URL in the background while it plays and keep the file under an
/// LRU size cap. Playback then prefers disk over the network, and it costs the
/// user nothing to manage: downloads are deliberate, this is automatic.
final class AudioCache: ObservableObject {
    static let shared = AudioCache()

    /// Roughly 600 songs at ~500 KB/min; tune from Settings later.
    private let limitBytes: Int64 = 512 * 1024 * 1024

    @Published private(set) var tracks: [Track] = []

    private let dir: URL
    private let metaURL: URL
    private var lastUsed: [String: Date] = [:]
    private var inFlight: Set<String> = []

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = caches.appendingPathComponent("AudioCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        metaURL = dir.appendingPathComponent("cache.json")
        load()
    }

    // MARK: Lookup

    private func fileURL(for id: String) -> URL { dir.appendingPathComponent("\(id).m4a") }

    /// A cached copy, if we have one. Touches its LRU stamp.
    func cachedURL(for id: String) -> URL? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        lastUsed[id] = Date()
        save()
        return url
    }

    func isCached(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    // MARK: Filling

    /// Store this track's audio in the background while it streams.
    func cache(_ track: Track, from url: URL) {
        let id = track.videoId
        guard !id.isEmpty, !isCached(id), !inFlight.contains(id) else { return }
        // Downloads already keep a permanent copy; don't duplicate it.
        guard Downloads.shared.localAudioURL(for: id) == nil else { return }
        inFlight.insert(id)
        let dest = fileURL(for: id)

        Task.detached(priority: .background) { [weak self] in
            var req = URLRequest(url: url)
            req.setValue(YouTube.visionUA, forHTTPHeaderField: "User-Agent")

            var stored = false
            if let (tmp, response) = try? await URLSession.shared.download(for: req),
               (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 {
                try? FileManager.default.removeItem(at: dest)
                stored = (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil
            }

            await MainActor.run {
                guard let self else { return }
                self.inFlight.remove(id)
                guard stored else { return }
                self.lastUsed[id] = Date()
                self.tracks.removeAll { $0.videoId == id }
                self.tracks.insert(track, at: 0)
                self.save()
                self.evictIfNeeded()
            }
        }
    }

    // MARK: Housekeeping

    var sizeBytes: Int64 {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]))?
            .reduce(Int64(0)) { total, url in
                total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            } ?? 0
    }

    /// Drop the least-recently-played files until we're back under the cap.
    private func evictIfNeeded() {
        guard sizeBytes > limitBytes else { return }
        let order = tracks.sorted {
            (lastUsed[$0.videoId] ?? .distantPast) < (lastUsed[$1.videoId] ?? .distantPast)
        }
        for track in order {
            guard sizeBytes > limitBytes else { break }
            remove(track.videoId)
        }
    }

    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
        tracks.removeAll { $0.videoId == id }
        lastUsed[id] = nil
        save()
    }

    func clear() {
        for track in tracks { try? FileManager.default.removeItem(at: fileURL(for: track.videoId)) }
        tracks = []
        lastUsed = [:]
        save()
    }

    // MARK: Persistence

    private struct Meta: Codable {
        let tracks: [Track]
        let lastUsed: [String: Date]
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Meta(tracks: tracks, lastUsed: lastUsed)) else { return }
        try? data.write(to: metaURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return }
        lastUsed = meta.lastUsed
        // Only keep entries whose file actually survived the system's cache purge.
        tracks = meta.tracks.filter { isCached($0.videoId) }
    }
}
