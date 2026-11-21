import AVFoundation

/// Keeps Blazify awake behind the lock screen while a TV or speaker plays.
///
/// iOS lets an app run in the background only while it is making sound. When songs go to a TV or
/// speaker the phone makes none, so a few seconds after locking iOS froze the app: the device
/// stopped hearing from the phone, dropped the connection, the music paused and the next song was
/// never sent. Playing silence here, for as long as the cast needs the phone, keeps the connection
/// and the lock-screen controls alive.
@MainActor
final class CastKeepAlive {
    static let shared = CastKeepAlive()

    private var player: AVAudioPlayer?
    private var stopLater: DispatchWorkItem?

    private init() {
        // A call or another app takes the sound away, and unplugged headphones pause it: start
        // again afterwards, or iOS freezes the app once more.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main,
        ) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            MainActor.assumeIsolated { CastKeepAlive.shared.playAgain() }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main,
        ) { _ in
            MainActor.assumeIsolated { CastKeepAlive.shared.playAgain() }
        }
    }

    /// Stay awake from now on.
    func hold() {
        stopLater?.cancel()
        stopLater = nil
        if player == nil {
            guard let silence = try? AVAudioPlayer(data: Self.silence) else { return }
            silence.numberOfLoops = -1
            silence.prepareToPlay()
            player = silence
        }
        playAgain()
    }

    /// Stop staying awake in [seconds], unless held again before then.
    func release(after seconds: TimeInterval) {
        guard player != nil else { return }
        stopLater?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.stop() }
        }
        stopLater = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func stop() {
        stopLater?.cancel()
        stopLater = nil
        player?.stop()
        player = nil
    }

    private func playAgain() {
        guard let player, !player.isPlaying else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
    }

    /// One second of silence as a WAV file: 8 kHz, one channel, 16-bit.
    private static let silence: Data = {
        let rate: UInt32 = 8000
        let samples = Data(count: Int(rate) * 2)
        var wav = Data()
        func put(_ text: String) { wav.append(contentsOf: Array(text.utf8)) }
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        put("RIFF"); put32(UInt32(36 + samples.count)); put("WAVE")
        put("fmt "); put32(16); put16(1); put16(1); put32(rate); put32(rate * 2); put16(2); put16(16)
        put("data"); put32(UInt32(samples.count))
        wav.append(samples)
        return wav
    }()
}
