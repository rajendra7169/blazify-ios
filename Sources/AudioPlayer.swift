import AVFoundation
import MediaPlayer
import Foundation

/// Now plays REAL YouTube audio: it asks the Blazify extractor backend to resolve
/// a videoId into a playable M4A URL, then streams that (directly from Google's
/// CDN) with background playback + lock-screen controls.
final class AudioPlayer: ObservableObject {

    @Published var isPlaying = false
    @Published var title = "Tap to load"
    @Published var status = ""

    private var player: AVPlayer?

    // The live server we deployed. Everything is HTTPS end to end.
    private let backend = "https://blazify-extractor-server.onrender.com"

    /// Resolve a YouTube videoId through the backend, then get ready to play it.
    func load(videoId: String) {
        configureSession()
        setupRemoteCommands()
        status = "Resolving…"
        title = "Loading…"

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
            let songTitle = (json["title"] as? String) ?? "Unknown"
            DispatchQueue.main.async {
                self.title = songTitle
                self.status = "Ready — press play"
                self.player = AVPlayer(url: streamURL)
                self.updateNowPlaying()
            }
        }.resume()
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        status = isPlaying ? "Playing" : "Paused"
        updateNowPlaying()
    }

    // MARK: - Audio session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: - Lock-screen / Control Center

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.player?.play(); self?.isPlaying = true; self?.updateNowPlaying(); return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause(); self?.isPlaying = false; self?.updateNowPlaying(); return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.toggle(); return .success
        }
    }

    private func updateNowPlaying() {
        let elapsed = player?.currentTime().seconds ?? 0
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Blazify",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
