import AVFoundation
import AVKit
import SwiftUI

/// The song's own video, playing behind the player.
///
/// `synced` means it follows the song second by second: the song is the video itself, or the
/// official video is the same length. Otherwise it is a different cut — a longer opening, a
/// shorter edit — and it runs on its own as a moving picture for the song.
struct SongVideo: Equatable {
    let videoId: String
    let url: URL
    let synced: Bool
}

/// Looked up once per song and remembered, a song with no video included.
actor SongVideos {
    static let shared = SongVideos()

    private struct Found {
        let video: SongVideo?
        let at: Date
    }

    private var known: [String: Found] = [:]
    private var pending: [String: Task<SongVideo?, Never>] = [:]

    /// Stream links stop working after a few hours, so an answer is trusted for less than that.
    private let keep: TimeInterval = 3 * 60 * 60

    /// "No video" may only mean the connection dropped, so that is asked again soon.
    private let keepNone: TimeInterval = 2 * 60

    /// How far apart a song and its video may be in length and still be the same cut.
    private let sameCutSeconds: Double = 3

    /// How many search results are looked through for the song's own music video.
    private let candidates = 5

    func forSong(_ track: Track, maxHeight: Int) async -> SongVideo? {
        let key = "\(track.videoId)@\(maxHeight)"
        if let found = known[key] {
            let age = Date().timeIntervalSince(found.at)
            if age < (found.video == nil ? keepNone : keep) { return found.video }
        }
        if let running = pending[key] { return await running.value }

        let task = Task<SongVideo?, Never> { [track, maxHeight] in
            await Self.find(track, maxHeight: maxHeight,
                            candidates: candidates, sameCutSeconds: sameCutSeconds)
        }
        pending[key] = task
        let found = await task.value
        known[key] = Found(video: found, at: Date())
        pending[key] = nil
        return found
    }

    private static func find(_ track: Track, maxHeight: Int,
                             candidates: Int, sameCutSeconds: Double) async -> SongVideo? {
        // A song that is itself a video already is the picture to show, and its own sound.
        if track.isVideo, !LocalMusic.isLocal(track.videoId) {
            guard let url = await YouTube.videoStreamURL(for: track.videoId, maxHeight: maxHeight)
            else { return nil }
            return SongVideo(videoId: track.videoId, url: url, synced: true)
        }

        // Otherwise the artist's official video — a fan upload or a lyric video is not the song's
        // picture. The same cut as the song follows it in step; a different cut runs on its own.
        guard !track.title.isEmpty, !LocalMusic.isLocal(track.videoId) else { return nil }
        let query = track.artist.isEmpty ? track.title : "\(track.title) \(track.artist)"
        let results = await YouTube.search(query, scope: .videos)
        let official = Array(results.prefix(candidates))
        guard !official.isEmpty else { return nil }

        let sameCut = official.first {
            track.duration > 0 && $0.duration > 0 && abs($0.duration - track.duration) <= sameCutSeconds
        }
        let candidate = sameCut ?? official[0]
        guard let url = await YouTube.videoStreamURL(for: candidate.videoId, maxHeight: maxHeight)
        else { return nil }
        return SongVideo(videoId: candidate.videoId, url: url, synced: sameCut != nil)
    }
}

/// The song's video, when there is one and it is worth the data.
///
/// A video is far heavier than a picture: on a metered connection it comes in a smaller size,
/// and not at all unless it has been asked for — the still artwork shows instead.
@MainActor
final class SongVideoLoader: ObservableObject {
    @Published private(set) var video: SongVideo?

    /// Why there is no picture, in a few words, or nil while one is playing.
    ///
    /// A player that shows the cover when it promised a video looks broken, and
    /// "it doesn't work" is the hardest report to act on. This is the screen
    /// saying which of the three things happened: the connection is not allowed,
    /// nothing was found, or the picture itself would not start.
    @Published private(set) var note: String?

    private var loadedFor: String?

    func load(for track: Track?, allowed: Bool, maxHeight: Int) {
        guard allowed else {
            video = nil
            loadedFor = nil
            note = String(localized: "Videos stay off on mobile data — Settings › Player and audio")
            return
        }
        guard let track else {
            video = nil
            loadedFor = nil
            note = nil
            return
        }
        let key = "\(track.videoId)@\(maxHeight)"
        guard key != loadedFor else { return }
        loadedFor = key
        video = nil
        note = String(localized: "Looking for a video…")
        Task {
            let found = await SongVideos.shared.forSong(track, maxHeight: maxHeight)
            // A later song may have overtaken this lookup while it ran.
            guard loadedFor == key else { return }
            video = found
            note = found == nil ? String(localized: "No video found for this song") : nil
        }
    }

    /// The picture was found but would not play. The cover stays, and this says so.
    func trouble(_ reason: String) {
        guard video != nil else { return }
        video = nil
        note = reason
    }
}

/// Plays the picture, muted, and keeps it in step with the song.
///
/// The song is never touched — it is the clock, and only the picture is nudged. A video that is
/// a different cut is left to run on its own, because seeking it to the song's position would
/// land somewhere that does not match anyway.
struct VideoArtView: UIViewRepresentable {
    let video: SongVideo
    /// Where the song is, in seconds.
    let position: Double
    let isPlaying: Bool
    /// Said when the picture will not start, so the screen can explain itself
    /// rather than showing the cover and leaving everyone to guess.
    var onTrouble: (String) -> Void = { _ in }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .clear   // the cover shows through until a frame arrives
        context.coordinator.onTrouble = onTrouble
        context.coordinator.attach(to: view, video: video)
        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        context.coordinator.onTrouble = onTrouble
        context.coordinator.update(video: video, position: position, isPlaying: isPlaying, view: view)
    }

    static func dismantleUIView(_ view: PlayerContainerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var player: AVPlayer?
        private var current: SongVideo?
        var onTrouble: (String) -> Void = { _ in }

        private var statusObs: NSKeyValueObservation?
        private var readyObs: NSKeyValueObservation?
        private var watchdog: Task<Void, Never>?

        /// How far out of step the picture may drift before it is nudged.
        private let tolerance: Double = 0.35

        /// How long a picture may take to show its first frame before it counts
        /// as never having started. Generous: a video is fetched alongside the
        /// song, and the song comes first.
        private let patience: UInt64 = 15

        func attach(to view: PlayerContainerView, video: SongVideo) {
            // The same user-agent the song is fetched with. Without it googlevideo
            // refuses the stream and the picture stays black — the song plays on,
            // so there is nothing on screen to say what went wrong.
            let asset = AVURLAsset(url: video.url,
                                   options: [AVURLAssetHTTPUserAgentKey: YouTube.visionUA])
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player.isMuted = true            // the song is the sound
            player.actionAtItemEnd = .none
            self.player = player
            self.current = video
            view.playerLayer.player = player
            view.playerLayer.videoGravity = .resizeAspectFill
            // Nothing is heard from it, so it starts the moment it can.
            player.play()

            // Three ways this can go wrong, and all three used to look the same
            // from the outside: the item refuses, the layer never has a frame to
            // show, or it simply never arrives.
            let item = player.currentItem
            statusObs = item?.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                let reason = item.error?.localizedDescription ?? "the video would not load"
                Task { @MainActor [weak self] in self?.onTrouble(reason) }
            }
            readyObs = view.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                if layer.isReadyForDisplay { self?.watchdog?.cancel() }
            }
            watchdog?.cancel()
            watchdog = Task { [weak self, weak view] in
                try? await Task.sleep(nanoseconds: (self?.patience ?? 15) * 1_000_000_000)
                guard !Task.isCancelled, let view, !view.playerLayer.isReadyForDisplay else { return }
                await MainActor.run { self?.onTrouble("The video never started playing") }
            }

            // A cut of its own just loops; there is nothing to stay in step with.
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem, queue: .main,
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }

        func update(video: SongVideo, position: Double, isPlaying: Bool, view: PlayerContainerView) {
            if current != video {
                stop()
                attach(to: view, video: video)
            }
            guard let player else { return }

            if video.synced {
                let at = player.currentTime().seconds
                if at.isFinite, abs(at - position) > tolerance {
                    player.seek(to: CMTime(seconds: position, preferredTimescale: 600),
                                toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }

            if isPlaying, player.rate == 0 {
                player.play()
            } else if !isPlaying, player.rate != 0 {
                player.pause()
            }
        }

        func stop() {
            NotificationCenter.default.removeObserver(self)
            statusObs = nil
            readyObs = nil
            watchdog?.cancel()
            watchdog = nil
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
            current = nil
        }
    }
}

/// A plain view whose layer is the player's, so the picture resizes with it.
final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
