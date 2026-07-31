import AVFoundation
import Foundation
import UIKit

/// Music that came from the phone rather than from YouTube — anything you pick
/// out of Files, iCloud Drive or another app's share sheet.
///
/// Picked files are COPIED into our own container rather than referenced in
/// place. A security-scoped bookmark would save the disk space, but it goes
/// stale the moment the file moves, the provider unmounts, or iCloud evicts the
/// local copy — and a library that silently loses songs is worse than one that
/// costs a few megabytes. Once copied, a local song is just a `Track` whose id
/// starts with `local-`, so the queue, favourites, history and every list screen
/// treat it exactly like anything else.
final class LocalMusic: ObservableObject {
    static let shared = LocalMusic()

    /// The marker that tells the rest of the app not to go to the network for
    /// this song. Video ids from YouTube are 11 characters and never contain a
    /// hyphen in this position, so there's no chance of a collision.
    static let prefix = "local-"

    static func isLocal(_ videoId: String) -> Bool { videoId.hasPrefix(prefix) }

    @Published private(set) var tracks: [Track] = []      // newest first
    @Published private(set) var importing = false
    @Published private(set) var findingArt = false
    @Published private(set) var sizeBytes: Int64 = 0

    private let dir: URL
    private let metaURL: URL
    /// id → the file we wrote, which keeps whatever extension it arrived with.
    private var files: [String: String] = [:]

    private struct Entry: Codable {
        let track: Track
        let file: String
    }

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("LocalMusic", isDirectory: true)
        metaURL = dir.appendingPathComponent("library.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadMeta()
        refreshSize()
    }

    // MARK: Lookup — the hooks the player and artwork use

    func localAudioURL(for id: String) -> URL? {
        guard let name = files[id] else { return nil }
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func localArtURL(for id: String) -> URL? {
        let url = dir.appendingPathComponent("\(id).jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func duration(for id: String) -> Double? {
        tracks.first { $0.videoId == id }?.duration
    }

    // MARK: Import

    /// Copy in what the picker handed us and read each file's own tags.
    /// Returns how many actually landed, so the UI can say something true when
    /// a file turns out to be unreadable.
    @discardableResult
    func importFiles(_ urls: [URL]) async -> Int {
        await MainActor.run { importing = true }
        var added = 0
        for url in urls {
            if await copyIn(url) { added += 1 }
        }
        await MainActor.run {
            saveMeta()
            refreshSize()
            importing = false
        }
        Task { await self.fetchMissingArtwork() }
        return added
    }

    /// Look up covers online for files that had none embedded.
    ///
    /// Best effort, and deliberately quiet: it matches on title and artist, so
    /// it can pick the wrong release — but a plausible cover beats a blank tile,
    /// and nothing about the audio changes. Runs once per song; a file that
    /// stays unmatched is retried on the next visit, which costs one search.
    @discardableResult
    func fetchMissingArtwork() async -> Int {
        guard !findingArt else { return 0 }
        let missing = tracks.filter { localArtURL(for: $0.videoId) == nil }
        guard !missing.isEmpty else { return 0 }
        await MainActor.run { findingArt = true }
        defer { Task { @MainActor in self.findingArt = false } }

        var found = 0
        for track in missing {
            let query = [track.title, track.artist]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !query.isEmpty else { continue }
            guard let match = await YouTube.search(query).first,
                  let remote = match.artURL(size: 1080),
                  let data = await ArtFetch.data(from: remote),
                  let image = UIImage(data: data),
                  let jpeg = Self.squared(image).jpegData(compressionQuality: 0.9)
            else { continue }

            let artURL = dir.appendingPathComponent("\(track.videoId).jpg")
            try? jpeg.write(to: artURL, options: .atomic)
            let id = track.videoId
            let path = artURL.absoluteString
            await MainActor.run {
                if let i = self.tracks.firstIndex(where: { $0.videoId == id }) {
                    let old = self.tracks[i]
                    self.tracks[i] = Track(videoId: old.videoId, title: old.title,
                                           artist: old.artist, thumbnail: path,
                                           duration: old.duration)
                }
            }
            found += 1
        }
        await MainActor.run {
            self.saveMeta()
            self.refreshSize()
        }
        return found
    }

    private func copyIn(_ source: URL) async -> Bool {
        // A picked file lives outside our sandbox; without this the copy fails
        // with a permission error that looks like the file doesn't exist.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let id = Self.prefix + UUID().uuidString
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        let destination = dir.appendingPathComponent("\(id).\(ext)")
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            return false
        }

        let asset = AVURLAsset(url: destination)
        var title = source.deletingPathExtension().lastPathComponent
        var artist = ""
        var seconds = 0.0
        var artData: Data?

        if let duration = try? await asset.load(.duration) {
            seconds = CMTimeGetSeconds(duration)
            if !seconds.isFinite || seconds < 0 { seconds = 0 }
        }
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                switch item.commonKey {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue), !value.isEmpty { title = value }
                case .commonKeyArtist, .commonKeyAuthor:
                    if artist.isEmpty, let value = try? await item.load(.stringValue) { artist = value }
                case .commonKeyArtwork:
                    if artData == nil { artData = try? await item.load(.dataValue) }
                default: break
                }
            }
        }

        // Embedded cover art gets squared and written beside the audio, so the
        // rest of the app can point at a plain file:// like it does for a
        // downloaded song.
        var thumbnail = ""
        if let artData, let image = UIImage(data: artData) {
            let artURL = dir.appendingPathComponent("\(id).jpg")
            if let jpeg = Self.squared(image).jpegData(compressionQuality: 0.9) {
                try? jpeg.write(to: artURL, options: .atomic)
                thumbnail = artURL.absoluteString
            }
        }

        let track = Track(videoId: id, title: title, artist: artist,
                          thumbnail: thumbnail, duration: seconds)
        await MainActor.run {
            files[id] = destination.lastPathComponent
            tracks.insert(track, at: 0)
        }
        return true
    }

    private static func squared(_ image: UIImage) -> UIImage {
        let side = min(max(image.size.width, image.size.height), 1000)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                       format: format).image { _ in
            let ratio = max(side / max(image.size.width, 1), side / max(image.size.height, 1))
            let box = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.draw(in: CGRect(x: (side - box.width) / 2, y: (side - box.height) / 2,
                                  width: box.width, height: box.height))
        }
    }

    // MARK: Removal

    func remove(_ id: String) {
        if let name = files[id] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).jpg"))
        files[id] = nil
        tracks.removeAll { $0.videoId == id }
        saveMeta()
        refreshSize()
    }

    func removeAll() {
        for id in Array(files.keys) { remove(id) }
    }

    // MARK: Storage

    func refreshSize() {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: Array(keys))) ?? []
        sizeBytes = contents.reduce(0) {
            $0 + Int64((try? $1.resourceValues(forKeys: keys).fileSize) ?? 0)
        }
    }

    private func saveMeta() {
        let entries = tracks.compactMap { track -> Entry? in
            guard let file = files[track.videoId] else { return nil }
            return Entry(track: track, file: file)
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: metaURL, options: .atomic)
    }

    private func loadMeta() {
        guard let data = try? Data(contentsOf: metaURL),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        // A reinstall gets a new container, so a saved artwork path from the old
        // one is dead. The id is stable, so rebuild the path rather than trust it.
        tracks = entries.map { entry in
            var track = entry.track
            if !track.thumbnail.isEmpty, let art = localArtURL(for: track.videoId) {
                track = Track(videoId: track.videoId, title: track.title, artist: track.artist,
                              thumbnail: art.absoluteString, duration: track.duration)
            }
            return track
        }
        files = Dictionary(uniqueKeysWithValues: entries.map { ($0.track.videoId, $0.file) })
    }
}
