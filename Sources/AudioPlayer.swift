import AVFoundation
import MediaPlayer

/// Bare-minimum background-capable player. Its only job is to prove the pipeline:
/// build without a Mac -> SideStore install -> audio that survives screen lock,
/// with working lock-screen controls. It plays one fixed public file, so this
/// test does NOT depend on the YouTube extractor yet — that comes next.
final class AudioPlayer: ObservableObject {

    @Published var isPlaying = false
    let title = "Blazify Test Track"

    private var player: AVPlayer?

    // A stable, public sample track. Swapped for a real stream URL once the
    // extractor backend exists.
    private let url = URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")!

    func prepare() {
        configureSession()
        if player == nil {
            player = AVPlayer(url: url)
        }
        setupRemoteCommands()
        updateNowPlaying()
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlaying()
    }

    // MARK: - Audio session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // `.playback` is what keeps sound alive when the screen locks. The default
        // category silences on lock — the classic "music stops when I lock it" bug.
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
