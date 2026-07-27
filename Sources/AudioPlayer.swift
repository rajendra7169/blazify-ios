import AVFoundation
import MediaPlayer
import UIKit
import Foundation

/// Streams real YouTube audio resolved by the Blazify extractor backend, and
/// publishes everything the player UI needs: art, artist, duration, live
/// position, plus background playback and lock-screen controls (with artwork).
final class AudioPlayer: ObservableObject {

    @Published var title = "Tap to load"
    @Published var artist = ""
    @Published var thumbnailURL: URL?
    @Published var isPlaying = false
    @Published var duration: Double = 0    // seconds, from the backend
    @Published var currentTime: Double = 0 // seconds, from the player
    @Published var status = ""

    /// 0…1 for the progress bar.
    var progress: Double { duration > 0 ? min(max(currentTime / duration, 0), 1) : 0 }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var artwork: MPMediaItemArtwork?

    private let backend = "https://blazify-extractor-server.onrender.com"

    // MARK: - Load

    func load(videoId: String) {
        configureSession()
        setupRemoteCommands()
        status = "Resolving…"
        title = "Loading…"
        artist = ""
        thumbnailURL = nil
        artwork = nil
        currentTime = 0
        duration = 0
        isPlaying = false

        guard let url = URL(string: "\(backend)/stream?v=\(videoId)") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            if let error = error {
                DispatchQueue.main.async { self.status = "Network error: \(error.localizedDescription)" }
                return
            }
            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                DispatchQueue.main.async { self.status = "Bad response" }
                return
            }
            if let err = json["error"] as? String {
                DispatchQueue.main.async { self.status = "Server: \(err)" }
                return
            }
            guard
                let streamStr = json["url"] as? String,
                let streamURL = URL(string: streamStr)
            else {
                DispatchQueue.main.async { self.status = "No stream URL" }
                return
            }
            DispatchQueue.main.async {
                self.title = (json["title"] as? String) ?? "Unknown"
                self.artist = (json["artist"] as? String) ?? ""
                self.duration = (json["duration"] as? Double) ?? (json["duration"] as? NSNumber)?.doubleValue ?? 0
                if let t = json["thumbnail"] as? String, let turl = URL(string: t) {
                    self.thumbnailURL = turl
                    self.loadArtwork(turl)
                }
                self.status = "Ready"
                self.startPlayer(streamURL)
            }
        }.resume()
    }

    private func startPlayer(_ url: URL) {
        removeTimeObserver()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main,
        ) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds.isFinite ? time.seconds : 0
        }
        updateNowPlaying()
    }

    // MARK: - Controls

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        status = isPlaying ? "Playing" : "Paused"
        updateNowPlaying()
    }

    func seek(to fraction: Double) {
        guard duration > 0, let player else { return }
        let target = fraction * duration
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
        updateNowPlaying()
    }

    // MARK: - Session / remote / now-playing

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            self?.player?.play(); self?.isPlaying = true; self?.updateNowPlaying(); return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause(); self?.isPlaying = false; self?.updateNowPlaying(); return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
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

    private func loadArtwork(_ url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let img = UIImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            DispatchQueue.main.async { self.artwork = art; self.updateNowPlaying() }
        }.resume()
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist.isEmpty ? "Blazify" : artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func removeTimeObserver() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }
}
