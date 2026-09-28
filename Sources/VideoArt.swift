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

        // Otherwise the artist's own video, and only that. A lyric video, a fan
        // upload, a slowed-and-reverbed edit — those are what a plain search
        // hands back first, and none of them is the song's picture. YouTube
        // marks its own with OMV, which is what the Android player looks for and
        // why its videos look like music videos.
        guard !track.title.isEmpty, !LocalMusic.isLocal(track.videoId) else { return nil }
        let query = track.artist.isEmpty ? track.title : "\(track.title) \(track.artist)"
        let results = await YouTube.search(query, scope: .videos)
        let official = results.prefix(candidates).filter(\.isOfficialVideo)
        guard !official.isEmpty else { return nil }

        // The same cut as the song follows it in step; a different cut runs on its own.
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

/// The picture outlives the screen it is shown on.
///
/// The full player is presented as a cover, so closing it takes the whole view
/// down — and with it, until now, the video: reopening built a new player,
/// fetched the stream again and sat black for seconds. On Android the player
/// sheet is never destroyed, only collapsed, which is why its picture is simply
/// there when the sheet comes back up.
///
/// So the player is kept here instead. Closing the screen only rests it — paused,
/// with everything it has already fetched — and opening it again hands the same
/// player to the new layer. A different song releases it, since its buffer is of
/// no use to the next one.
final class VideoArtPlayers {
    static let shared = VideoArtPlayers()

    private var url: URL?
    private var kept: AVPlayer?
    private var output: AVPlayerItemVideoOutput?

    /// The player for this video, made once and lent out afterwards.
    func player(for video: SongVideo) -> (player: AVPlayer, output: AVPlayerItemVideoOutput?, fresh: Bool) {
        if url == video.url, let kept { return (kept, output, false) }
        release()

        let asset = AVURLAsset(url: video.url,
                               options: [AVURLAssetHTTPUserAgentKey: YouTube.visionUA])
        let item = AVPlayerItem(asset: asset)
        // Two seconds in hand is plenty for a picture. Waiting for the player's
        // usual comfortable buffer is seconds of black.
        item.preferredForwardBufferDuration = 2
        let made = AVPlayer(playerItem: item)
        made.isMuted = true              // the song is the sound
        made.actionAtItemEnd = .none
        made.automaticallyWaitsToMinimizeStalling = false

        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(videoOutput)

        url = video.url
        kept = made
        output = videoOutput
        return (made, videoOutput, true)
    }

    /// The screen has gone; the picture waits where it is.
    func rest() { kept?.pause() }

    func release() {
        kept?.pause()
        kept?.replaceCurrentItem(with: nil)
        kept = nil
        output = nil
        url = nil
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
    /// How long the song is, for placing a video that is a different cut of it.
    var songLength: Double = 0
    /// Said when the picture will not start, so the screen can explain itself
    /// rather than showing the cover and leaving everyone to guess.
    var onTrouble: (String) -> Void = { _ in }
    /// Said the moment there is a real frame on screen. Until then the artwork
    /// underneath is what should be seen — a layer with nothing in it yet is
    /// just black over the cover.
    var onFirstFrame: () -> Void = { }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .clear   // the cover shows through until a frame arrives
        context.coordinator.onTrouble = onTrouble
        context.coordinator.onFirstFrame = onFirstFrame
        context.coordinator.attach(to: view, video: video)
        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        context.coordinator.onTrouble = onTrouble
        context.coordinator.onFirstFrame = onFirstFrame
        context.coordinator.update(video: video, position: position, songLength: songLength,
                                   isPlaying: isPlaying, view: view)
    }

    static func dismantleUIView(_ view: PlayerContainerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var player: AVPlayer?
        private var current: SongVideo?
        var onTrouble: (String) -> Void = { _ in }
        var onFirstFrame: () -> Void = { }

        private var statusObs: NSKeyValueObservation?
        private var readyObs: NSKeyValueObservation?
        private var watchdog: Task<Void, Never>?
        private var output: AVPlayerItemVideoOutput?
        private var bandsLook: Task<Void, Never>?
        /// The thinnest bands seen so far, so one dark scene cannot decide it.
        private var bands: Double = 1

        /// Close enough to the sound that nobody could tell.
        private let inStep: Double = 0.08

        /// Further apart than this and the picture jumps to the song rather than
        /// catching up. Anything smaller is made up by running it a little fast
        /// or a little slow, which nobody notices without the sound — where
        /// seeking every quarter second, as this used to, is a visible stutter.
        private let jumpBeyond: Double = 2

        /// How far ahead of the song a jump aims, learned from how far each jump
        /// actually landed out, and never more than four seconds.
        private var lead: Double = 0.8
        private var justJumped = false
        private let maxLead: Double = 4

        /// A cut of its own is put roughly where the song is, once, and again
        /// whenever the listener moves the song themselves.
        private var placed = false
        private var lastPosition: Double = 0

        /// Label logos and title cards at the start of a video, skipped when it
        /// runs on its own.
        private let openingTitles: Double = 6

        /// How long a picture may take to show its first frame before it counts
        /// as never having started. Generous: a video is fetched alongside the
        /// song, and the song comes first.
        private let patience: UInt64 = 15

        func attach(to view: PlayerContainerView, video: SongVideo) {
            // Lent out rather than built: a player kept from the last time this
            // screen was open already holds what it fetched, so reopening shows
            // a picture instead of buffering one.
            let lent = VideoArtPlayers.shared.player(for: video)
            let player = lent.player
            self.player = player
            self.current = video
            self.output = lent.output
            view.playerLayer.player = player
            view.playerLayer.videoGravity = .resizeAspectFill
            // Whatever the song before it was zoomed to, this one starts square.
            view.playerLayer.transform = CATransform3DIdentity
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
                guard layer.isReadyForDisplay else { return }
                self?.watchdog?.cancel()
                Task { @MainActor [weak self] in self?.onFirstFrame() }
            }
            // A few frames are looked at, spread out, for the black bands some
            // videos carry above and below the picture.
            self.bands = 1
            bandsLook?.cancel()
            bandsLook = Task { [weak self, weak view] in
                for wait in [0.4, 1.2, 2.0, 4.0, 8.0] {
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    guard !Task.isCancelled, let self, let view else { return }
                    await self.lookForBands(in: view)
                }
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
                let length = player?.currentItem?.duration.seconds ?? 0
                let from = length.isFinite && length > 0 ? min(6, length / 4) : 0
                player?.seek(to: CMTime(seconds: from, preferredTimescale: 600))
                player?.play()
            }
        }

        func update(video: SongVideo, position: Double, songLength: Double,
                    isPlaying: Bool, view: PlayerContainerView) {
            if current != video {
                stop()
                placed = false
                lead = 0.8
                attach(to: view, video: video)
            }
            guard let player else { return }
            defer { lastPosition = position }

            guard isPlaying else {
                if player.rate != 0 { player.pause() }
                return
            }
            if player.rate == 0 { player.play() }
            guard player.currentItem?.status == .readyToPlay else { return }

            // The listener dragged the progress bar. Both kinds of picture have
            // to answer that — one follows the song's second, the other is put
            // back to roughly the same distance through itself.
            let moved = abs(position - lastPosition) > jumpBeyond

            guard video.synced else {
                if !placed || moved { place(player, at: position, songLength: songLength) }
                return
            }

            let at = player.currentTime().seconds
            guard at.isFinite else { return }
            let drift = position - at

            if justJumped {
                // Half the miss, so one slow answer does not throw the next jump far off.
                lead = min(max(lead + drift / 2, 0), maxLead)
                justJumped = false
            }

            if abs(drift) > jumpBeyond {
                player.rate = 1
                player.seek(to: CMTime(seconds: position + lead, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero)
                justJumped = true
            } else if abs(drift) > inStep {
                // Made up by running the picture a touch fast or slow instead of
                // jumping it, which is what makes this look smooth.
                player.rate = Float(1 + min(max(drift / 4, -0.25), 0.25))
            } else if player.rate != 1 {
                player.rate = 1
            }
        }

        /// Puts a video that is a different cut about as far through itself as the
        /// song is through itself, and never on the opening titles.
        private func place(_ player: AVPlayer, at position: Double, songLength: Double) {
            let length = player.currentItem?.duration.seconds ?? 0
            guard length.isFinite, length > 0 else { return }
            let along = songLength > 0 ? position / songLength : 0
            let target = max(along * length, min(openingTitles, length / 4))
            player.seek(to: CMTime(seconds: min(target, length - 1), preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
            placed = true
        }

        /// Reads one frame and, if it has bands, brings the picture in past them.
        @MainActor
        private func lookForBands(in view: PlayerContainerView) {
            guard let output, let player else { return }
            let time = player.currentTime()
            guard output.hasNewPixelBuffer(forItemTime: time),
                  let buffer = output.copyPixelBuffer(forItemTime: time,
                                                      itemTimeForDisplay: nil)
            else { return }

            guard let rows = Self.brightness(of: buffer),
                  let share = Letterbox.share(rows: rows)
            else { return }

            bands = min(bands, share)
            let zoom = Letterbox.zoom(for: bands == 1 ? 0 : bands)
            guard abs(view.playerLayer.transform.m11 - CGFloat(zoom)) > 0.001 else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.6)
            view.playerLayer.transform = CATransform3DMakeScale(CGFloat(zoom), CGFloat(zoom), 1)
            CATransaction.commit()
        }

        /// A coarse grid of brightnesses off one frame: enough to find a band,
        /// cheap enough to read five times a song.
        private static func brightness(of buffer: CVPixelBuffer) -> [[Double]]? {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            guard width > 8, height > 8 else { return nil }

            let columns = 48, lines = 54
            var rows: [[Double]] = []
            rows.reserveCapacity(lines)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for line in 0..<lines {
                let y = line * (height - 1) / (lines - 1)
                var row: [Double] = []
                row.reserveCapacity(columns)
                for column in 0..<columns {
                    let x = column * (width - 1) / (columns - 1)
                    let at = y * stride + x * 4          // BGRA
                    let blue = Double(bytes[at]), green = Double(bytes[at + 1]), red = Double(bytes[at + 2])
                    row.append((red * 299 + green * 587 + blue * 114) / 1000)
                }
                rows.append(row)
            }
            return rows
        }

        /// The screen is going. Everything watching it goes with it — the
        /// picture itself is left where it is, paused, for when it comes back.
        func stop() {
            NotificationCenter.default.removeObserver(self)
            statusObs = nil
            readyObs = nil
            watchdog?.cancel()
            watchdog = nil
            bandsLook?.cancel()
            bandsLook = nil
            output = nil
            player = nil
            current = nil
            VideoArtPlayers.shared.rest()
        }
    }
}

/// A plain view whose layer is the player's, so the picture resizes with it.
final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// How much of a frame is black band at the top and again at the bottom.
///
/// Some videos carry a cinema-shaped picture inside a television-shaped frame,
/// and those bands do not belong on a player whose whole point is the picture.
/// The thinner of the two bands is taken, so a dark sky at the top is not
/// mistaken for one. A frame that is dark nearly all over says nothing either
/// way and gives nil.
///
/// Pure arithmetic over a row of samples, so it can be checked without a video.
enum Letterbox {
    /// Brightness, out of 255, below which a pixel counts as band.
    static let dark: Double = 24

    /// How much of a band's row a logo or a name printed in it may cover.
    static let printShare = 0.25

    /// Bands thinner than this are left alone; more than this is a dark scene.
    static let smallest = 0.04
    static let largest = 0.22

    /// `rows` is the brightness of a grid of samples, top row first.
    static func share(rows: [[Double]]) -> Double? {
        guard let width = rows.first?.count, width > 0, rows.count > 4 else { return nil }
        func isBand(_ row: [Double]) -> Bool {
            row.filter { $0 >= dark }.count <= Int(Double(width) * printShare)
        }
        var top = 0
        while top < rows.count / 2, isBand(rows[top]) { top += 1 }
        var bottom = 0
        while bottom < rows.count / 2, isBand(rows[rows.count - 1 - bottom]) { bottom += 1 }
        let share = Double(min(top, bottom)) / Double(rows.count)
        if share > largest { return nil }          // a dark scene, not a band
        return share >= smallest ? share : 0
    }

    /// How far in to zoom so bands of `share` each fall outside the frame.
    static func zoom(for share: Double) -> Double {
        share > 0 ? 1 / (1 - 2 * share) : 1
    }
}
