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
    /// Bytes on disk, published so Settings never has to stat files in a body.
    @Published private(set) var sizeBytes: Int64 = 0

    private let dir: URL

    /// Recount in the background and publish.
    func refreshSize() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let size = await self.measure()
            await MainActor.run { self.sizeBytes = size }
        }
    }

    private func measure() -> Int64 {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]))?
            .reduce(Int64(0)) { total, url in
                total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            } ?? 0
    }

    /// Delete every downloaded file and forget them.
    func clearAll() {
        for track in tracks { remove(track.videoId) }
        tracks = []
        sizeBytes = 0
        saveMeta()
    }
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

    // Queued, two at a time. Six at once used to fire six full pipelines in
    // parallel — thirty-plus requests contending — and some tasks just died.
    private var pending: [Track] = []
    private var activeCount = 0
    private let maxConcurrent = 2

    func download(_ track: Track) {
        let id = track.videoId
        guard !id.isEmpty, state(id) == .none else { return }
        states[id] = .downloading
        pending.append(track)
        pump()
    }

    func downloadAll(_ tracks: [Track]) {
        for t in tracks { download(t) }
    }

    private func pump() {
        while activeCount < maxConcurrent, !pending.isEmpty {
            let next = pending.removeFirst()
            activeCount += 1
            Task {
                await perform(next)
                await MainActor.run {
                    self.activeCount -= 1
                    self.pump()
                }
            }
        }
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
        // One retry: a burst of enqueues sometimes drops the first resolve.
        var stream = await YouTube.streamURL(for: id)
        if stream == nil {
            try? await Task.sleep(nanoseconds: 800_000_000)
            stream = await YouTube.streamURL(for: id)
        }
        guard let stream else {
            await MainActor.run { self.states[id] = DownloadState.none }
            return
        }
        var req = URLRequest(url: stream.url)
        req.setValue(YouTube.visionUA, forHTTPHeaderField: "User-Agent")

        do {
            let (tmp, _) = try await URLSession.shared.download(for: req)
            try? FileManager.default.removeItem(at: audioURL(for: id))
            try FileManager.default.moveItem(at: tmp, to: audioURL(for: id))

            // The song is offline the moment the audio lands — mark it done NOW.
            // Art and lyrics used to run first, which meant a five-provider
            // lyrics hunt before the row would even say "downloaded".
            let stored = Track(videoId: id, title: track.title, artist: track.artist,
                               thumbnail: track.thumbnail, duration: stream.duration)
            await MainActor.run {
                self.durations[id] = stream.duration
                self.tracks.removeAll { $0.videoId == id }
                self.tracks.insert(stored, at: 0)
                self.states[id] = .done
                self.saveMeta()
                self.refreshSize()
            }
            await enrich(track, id: id, duration: stream.duration)
        } catch {
            await MainActor.run { self.states[id] = DownloadState.none }
        }
    }

    /// Best-effort offline extras after the audio is safe: artwork on disk and
    /// lyrics, via the shared cache so a warm fetch isn't repeated.
    private func enrich(_ track: Track, id: String, duration: Double) async {
        if let remote = track.thumbnailURL,
           let (adata, _) = try? await URLSession.shared.data(from: remote) {
            try? adata.write(to: artURL(for: id))
            let artPath = self.localArt(for: id) ?? track.thumbnail
            await MainActor.run {
                // Remember where it came from before the row points at the file.
                self.remoteArt[id] = track.thumbnail
                if let i = self.tracks.firstIndex(where: { $0.videoId == id }) {
                    self.tracks[i] = Track(videoId: id, title: track.title, artist: track.artist,
                                           thumbnail: artPath, duration: duration)
                    self.saveMeta()
                }
            }
        }

        let candidates = await LyricsCache.shared.warm(videoId: id, title: track.title,
                                                       artist: track.artist, duration: duration)
        if let lyrics = Lyrics.best(candidates) {
            if let lrc = lyrics.raw {
                try? lrc.write(to: lyricsURL(for: id), atomically: true, encoding: .utf8)
            } else if let plain = lyrics.plain {
                try? plain.write(to: plainLyricsURL(for: id), atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: Persistence

    /// Remote art URL per song, so a re-save never persists a container path.
    private var remoteArt: [String: String] = [:]

    private struct StoredTrack: Codable {
        let videoId, title, artist, thumbnail: String
        let duration: Double
    }
    private struct Meta: Codable {
        let tracks: [StoredTrack]
        let durations: [String: Double]
    }

    /// Derivable from the video id alone, so it always resolves even when the
    /// catalogue thumbnail we saved has been lost.
    static func fallbackArt(_ videoId: String) -> String {
        "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
    }

    /// The on-disk art for a song, as a URL string, if we fetched it.
    private func localArt(for id: String) -> String? {
        let u = artURL(for: id)
        return FileManager.default.fileExists(atPath: u.path) ? u.absoluteString : nil
    }

    private func saveMeta() {
        // Persist the REMOTE thumbnail, never the local file:// path: the app
        // container's UUID changes on every reinstall, which left every
        // downloaded song art-less after a new build. The local copy is
        // resolved fresh in loadMeta().
        let stored = tracks.map {
            StoredTrack(videoId: $0.videoId, title: $0.title, artist: $0.artist,
                        thumbnail: $0.thumbnail.hasPrefix("file:") ? (remoteArt[$0.videoId] ?? "")
                                                                   : $0.thumbnail,
                        duration: $0.duration)
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
            remoteArt[$0.videoId] = $0.thumbnail
            // Prefer the copy on disk, rebuilt against this install's container.
            // Anything else that no longer resolves — a file:// path saved by an
            // older build, or an empty slot — falls back to the thumbnail every
            // video has, so an upgraded install isn't left with blank rows.
            let stored = $0.thumbnail
            let usable = !stored.isEmpty && !stored.hasPrefix("file:")
            return Track(videoId: $0.videoId, title: $0.title, artist: $0.artist,
                         thumbnail: localArt(for: $0.videoId)
                                    ?? (usable ? stored : Downloads.fallbackArt($0.videoId)),
                         duration: $0.duration)
        }
        for t in tracks { states[t.videoId] = .done }
    }
}
