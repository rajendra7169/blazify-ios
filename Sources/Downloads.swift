import Foundation
import Combine

enum DownloadState: Equatable { case none, downloading, done }

/// On-device offline downloads: saves the resolved audio (+ artwork) to the
/// Documents dir keyed by videoId, and remembers metadata so tracks play with no
/// network. The Player checks `localAudioURL` before resolving a stream.
final class Downloads: ObservableObject {
    static let shared = Downloads()

    @Published private(set) var states: [String: DownloadState] = [:]
    @Published private(set) var tracks: [Track] = []   // downloaded, newest first

    private let dir: URL
    private let metaURL: URL
    private var durations: [String: Double] = [:]

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        metaURL = dir.appendingPathComponent("meta.json")
        loadMeta()
    }

    // MARK: Paths / queries

    private func audioURL(for id: String) -> URL { dir.appendingPathComponent("\(id).m4a") }
    private func artURL(for id: String) -> URL { dir.appendingPathComponent("\(id).jpg") }
    private func lyricsURL(for id: String) -> URL { dir.appendingPathComponent("\(id).lrc") }
    private func plainLyricsURL(for id: String) -> URL { dir.appendingPathComponent("\(id).txt") }

    /// Lyrics saved alongside a download, so they work with no network.
    func cachedLyrics(for id: String) -> LyricsResult? {
        if let lrc = try? String(contentsOf: lyricsURL(for: id), encoding: .utf8), !lrc.isEmpty {
            return LyricsResult(lines: Lyrics.parseLRC(lrc), plain: nil, synced: true, raw: lrc)
        }
        if let plain = try? String(contentsOf: plainLyricsURL(for: id), encoding: .utf8), !plain.isEmpty {
            return LyricsResult(lines: [], plain: plain, synced: false, raw: nil)
        }
        return nil
    }

    func localAudioURL(for id: String) -> URL? {
        let u = audioURL(for: id)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    func duration(for id: String) -> Double? { durations[id] }
    func state(_ id: String) -> DownloadState { states[id] ?? .none }
    func isDownloaded(_ id: String) -> Bool { states[id] == .done }

    // MARK: Actions

    func toggle(_ track: Track) {
        if isDownloaded(track.videoId) { remove(track.videoId) } else { download(track) }
    }

    func download(_ track: Track) {
        let id = track.videoId
        guard !id.isEmpty, state(id) == .none else { return }
        states[id] = .downloading
        Task { await perform(track) }
    }

    func downloadAll(_ tracks: [Track]) {
        for t in tracks { download(t) }
    }

    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: audioURL(for: id))
        try? FileManager.default.removeItem(at: artURL(for: id))
        try? FileManager.default.removeItem(at: lyricsURL(for: id))
        try? FileManager.default.removeItem(at: plainLyricsURL(for: id))
        tracks.removeAll { $0.videoId == id }
        durations[id] = nil
        states[id] = nil
        saveMeta()
    }

    private func perform(_ track: Track) async {
        let id = track.videoId
        guard let stream = await YouTube.streamURL(for: id) else {
            await MainActor.run { self.states[id] = DownloadState.none }
            return
        }
        var req = URLRequest(url: stream.url)
        req.setValue(YouTube.visionUA, forHTTPHeaderField: "User-Agent")

        do {
            let (tmp, _) = try await URLSession.shared.download(for: req)
            try? FileManager.default.removeItem(at: audioURL(for: id))
            try FileManager.default.moveItem(at: tmp, to: audioURL(for: id))

            // Cache artwork too, so offline art works.
            var artPath = track.thumbnail
            if let remote = track.thumbnailURL,
               let (adata, _) = try? await URLSession.shared.data(from: remote) {
                try? adata.write(to: artURL(for: id))
                artPath = artURL(for: id).absoluteString
            }

            // Cache lyrics too, so a downloaded song is fully offline.
            let candidates = await Lyrics.search(title: track.title, artist: track.artist)
            if let lyrics = Lyrics.best(candidates) {
                if let lrc = lyrics.raw {
                    try? lrc.write(to: lyricsURL(for: id), atomically: true, encoding: .utf8)
                } else if let plain = lyrics.plain {
                    try? plain.write(to: plainLyricsURL(for: id), atomically: true, encoding: .utf8)
                }
            }

            let stored = Track(videoId: id, title: track.title, artist: track.artist,
                               thumbnail: artPath, duration: stream.duration)
            await MainActor.run {
                self.durations[id] = stream.duration
                self.tracks.removeAll { $0.videoId == id }
                self.tracks.insert(stored, at: 0)
                self.states[id] = .done
                self.saveMeta()
            }
        } catch {
            await MainActor.run { self.states[id] = DownloadState.none }
        }
    }

    // MARK: Persistence

    private struct StoredTrack: Codable {
        let videoId, title, artist, thumbnail: String
        let duration: Double
    }
    private struct Meta: Codable {
        let tracks: [StoredTrack]
        let durations: [String: Double]
    }

    private func saveMeta() {
        let stored = tracks.map {
            StoredTrack(videoId: $0.videoId, title: $0.title, artist: $0.artist,
                        thumbnail: $0.thumbnail, duration: $0.duration)
        }
        if let data = try? JSONEncoder().encode(Meta(tracks: stored, durations: durations)) {
            try? data.write(to: metaURL)
        }
    }

    private func loadMeta() {
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return }
        durations = meta.durations
        tracks = meta.tracks.map {
            Track(videoId: $0.videoId, title: $0.title, artist: $0.artist,
                  thumbnail: $0.thumbnail, duration: $0.duration)
        }
        for t in tracks { states[t.videoId] = .done }
    }
}
