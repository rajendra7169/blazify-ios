import AVFoundation
import MediaPlayer
import UIKit
import Foundation

/// Queue-based player. Resolves each track on-device (VISIONOS) and STREAMS the
/// URL directly in AVPlayer — instant start, seek anywhere, background + lock
/// screen with artwork, auto-advance. No server, no downloading first.
final class Player: ObservableObject {

    @Published var queue: [Track] = []
    @Published var index = 0
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime = 0.0
    @Published var duration = 0.0
    /// Drives the full-player sheet.
    @Published var showFullPlayer = false
    /// Last playback error, surfaced in the UI when something fails.
    @Published var lastError: String?

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var hasTrack: Bool { current != nil }
    var progress: Double { duration > 0 ? min(max(currentTime / duration, 0), 1) : 0 }

    private var avPlayer: AVPlayer?
    private var timeObserver: Any?
    private var statusObs: NSKeyValueObservation?
    private var isSeeking = false
    private var artwork: MPMediaItemArtwork?

    init() {
        configureSession()
        setupRemoteCommands()
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.next()
        }
    }

    // MARK: - Queue control

    func play(_ tracks: [Track], startAt: Int) {
        queue = tracks
        index = startAt
        loadCurrent()
    }

    func next() {
        guard index < queue.count - 1 else { return }
        index += 1
        loadCurrent()
    }

    func prev() {
        if currentTime > 3 || index == 0 {
            seek(to: 0)
        } else {
            index -= 1
            loadCurrent()
        }
    }

    // MARK: - Load / stream

    private func loadCurrent() {
        guard let track = current else { return }
        duration = track.duration
        currentTime = 0
        isLoading = true
        lastError = nil
        artwork = nil
        loadArtwork(track.thumbnailURL)
        updateNowPlaying()

        let videoId = track.videoId
        Task {
            let url = await YouTube.streamURL(for: videoId)
            await MainActor.run {
                guard self.current?.videoId == videoId else { return }
                guard let url else {
                    self.isLoading = false
                    self.lastError = "Couldn't load this track. Try again."
                    return
                }
                self.playStream(url)
                self.prefetchNext()
            }
        }
    }

    /// Warm the next track's stream URL so tapping "next" resolves instantly.
    private func prefetchNext() {
        let n = index + 1
        guard queue.indices.contains(n) else { return }
        let vid = queue[n].videoId
        Task.detached { _ = await YouTube.streamURL(for: vid) }
    }

    private func playStream(_ url: URL) {
        removeTimeObserver()
        statusObs = nil

        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: YouTube.visionUA])
        let item = AVPlayerItem(asset: asset)
        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    let d = item.duration.seconds
                    if d.isFinite, d > 0 { self.duration = d }
                    self.updateNowPlaying()
                case .failed:
                    self.isLoading = false
                    self.lastError = item.error?.localizedDescription ?? "Playback failed"
                default:
                    break
                }
            }
        }

        let p = AVPlayer(playerItem: item)
        avPlayer = p
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main,
        ) { [weak self] time in
            guard let self, !self.isSeeking else { return }
            self.currentTime = time.seconds.isFinite ? time.seconds : 0
            if self.duration <= 0, let d = self.avPlayer?.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
                self.updateNowPlaying()
            }
        }
        p.play()
        isPlaying = true
        updateNowPlaying()
    }

    func toggle() {
        guard let avPlayer else { return }
        if isPlaying { avPlayer.pause() } else { avPlayer.play() }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func seek(to fraction: Double) {
        guard duration > 0, let avPlayer else { return }
        let target = fraction * duration
        isSeeking = true
        currentTime = target
        updateNowPlaying()
        avPlayer.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero,
        ) { [weak self] _ in
            self?.isSeeking = false
        }
    }

    // MARK: - Session / remote / now-playing

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.prev(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard
                let self,
                let e = event as? MPChangePlaybackPositionCommandEvent,
                self.duration > 0
            else { return .commandFailed }
            self.seek(to: e.positionTime / self.duration)
            return .success
        }
    }

    private func resume() { avPlayer?.play(); isPlaying = true; updateNowPlaying() }
    private func pause() { avPlayer?.pause(); isPlaying = false; updateNowPlaying() }

    private func loadArtwork(_ url: URL?) {
        guard let url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let img = UIImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            DispatchQueue.main.async { self.artwork = art; self.updateNowPlaying() }
        }.resume()
    }

    private func updateNowPlaying() {
        guard let track = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist.isEmpty ? "Blazify" : track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func removeTimeObserver() {
        if let timeObserver { avPlayer?.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }
}
