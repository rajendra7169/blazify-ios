import SwiftUI
import ShazamKit
import AVFoundation

/// "What's playing?" — song recognition, the iOS counterpart to Blazify
/// the ShazamKit screen.
///
/// Record a few seconds, turn it into a
/// Shazam *signature*, and POST that to Shazam's public tag endpoint. No
/// account, no API key, no entitlement — we build the signature
/// algorithm; on iOS ShazamKit generates the identical format for us.
struct RecognitionView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var player: Player
    @StateObject private var recognizer = Recognizer()

    var body: some View {
        ZStack {
            palette.scaffold.ignoresSafeArea()

            // Behind everything, and only while there is something going on.
            if recognizer.phase == .listening {
                FlyingNotes(color: palette.accent)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            if recognizer.phase == .finding {
                FindingSparks(color: palette.accent)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                Group {
                    switch recognizer.phase {
                    case .idle: ready
                    case .listening: listening
                    case .finding: finding
                    case .found:
                        if let match = recognizer.match { found(match) }
                    case .notFound: notFound
                    case .failed: failed
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))

                Spacer()
                Spacer().frame(height: 40)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: recognizer.phase)
        .onAppear { recognizer.begin() }
        .onDisappear { recognizer.stop() }
    }

    // MARK: States

    /// Waiting for a tap: the wave barely stirring inside the button.
    private var ready: some View {
        VStack(spacing: 24) {
            Button { recognizer.begin() } label: {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [palette.accent.opacity(0.3),
                                                      palette.accent.opacity(0.1), .clear],
                                             center: .center, startRadius: 0, endRadius: 100))
                        .frame(width: 200, height: 200)
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 160, height: 160)
                    SoundWaveBars(color: palette.onAccent, lively: false)
                        .frame(width: 84, height: 84)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recognise a song")

            Text("Tap to recognise")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.onSurface)
        }
    }

    /// Listening: rings of sound leaving the button and the wave dancing. The
    /// button itself stops it, as does Cancel.
    private var listening: some View {
        VStack(spacing: 24) {
            ZStack {
                SoundRipples(color: palette.accent)
                    .frame(width: 260, height: 260)
                Button { recognizer.stop() } label: {
                    ZStack {
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 160, height: 160)
                        SoundWaveBars(color: palette.onAccent, lively: true)
                            .frame(width: 96, height: 96)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop listening")
            }

            Text("Listening…")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.accent)

            Button { recognizer.stop() } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .padding(.horizontal, 28).padding(.vertical, 10)
                    .overlay(Capsule().stroke(palette.onSurface.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    /// Heard it; now asking what it was.
    private var finding: some View {
        VStack(spacing: 24) {
            FindingRing(color: palette.accent)
                .frame(width: 160, height: 160)
            Text("Finding the song…")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.onSurface)
        }
    }

    /// Listened, and nothing matched.
    private var notFound: some View {
        VStack(spacing: 20) {
            SongNotFoundArt()
                .frame(width: 220, height: 220)

            Text("Song not found")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.onSurface)

            Text("Hold your phone closer to the music, wait for a part with singing or a clear tune, and try again.")
                .font(.system(size: 15))
                .foregroundStyle(palette.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            tryAgain
        }
    }

    /// Couldn't listen at all — the microphone is off, or the audio never came.
    private var failed: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(width: 120, height: 120)
                .background(palette.surfaceHigh)
                .clipShape(Circle())

            Text(recognizer.status)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            tryAgain
        }
    }

    private var tryAgain: some View {
        Button { recognizer.begin() } label: {
            Label("Try again", systemImage: "arrow.clockwise")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.onAccent)
                .padding(.horizontal, 28).padding(.vertical, 14)
                .background(palette.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func found(_ match: Recognizer.Match) -> some View {
        VStack(spacing: 12) {
            RemoteImage(url: match.artworkURL, size: 140) { palette.onSurface.opacity(0.06) }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(match.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .multilineTextAlignment(.center)
            Text(match.artist)
                .font(.system(size: 15))
                .foregroundStyle(palette.onSurfaceVariant)

            // Recognition tells us what it is; playback still comes from YouTube.
            Button {
                Task {
                    let results = await YouTube.search("\(match.title) \(match.artist)")
                    guard !results.isEmpty else { return }
                    await MainActor.run {
                        player.play(results, startAt: 0)
                        player.openFullPlayer()
                        dismiss()
                    }
                }
            } label: {
                Label("Play in Blazify", systemImage: "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(palette.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { recognizer.begin() } label: {
                Text("Listen again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
    }
}

/// Records a few seconds, builds a Shazam signature locally, and asks Shazam's
/// public endpoint what it is.
///
/// Deliberately *not* `SHSession`: catalog matching through SHSession needs the
/// ShazamKit App Service enabled on the App ID, which a sideloaded build can't
/// have. `SHSignatureGenerator` is local and carries no such requirement.
@MainActor
final class Recognizer: ObservableObject {
    struct Match {
        let title: String
        let artist: String
        let artworkURL: URL?
    }

    /// Where an attempt has got to; the screen draws one picture per phase.
    enum Phase: Equatable {
        case idle, listening, finding, found, notFound, failed
    }

    @Published private(set) var phase: Phase = .idle
    /// Why the last attempt couldn't listen, shown with `.failed`.
    @Published private(set) var status = ""
    @Published private(set) var match: Match?

    /// Each attempt's number. Stopping moves it on, so an attempt still waiting
    /// on the microphone or the network finds it is no longer the current one
    /// and leaves the screen alone instead of announcing a stale result.
    private var run = 0
    private var job: Task<Void, Never>?

    private let engine = AVAudioEngine()
    private let sampleSeconds = 6.0

    private static let userAgents = [
        "Dalvik/2.1.0 (Linux; U; Android 5.0.2; VS980 4G Build/LRX22G)",
        "Dalvik/2.1.0 (Linux; U; Android 6.0.1; SM-G920F Build/MMB29K)",
        "Dalvik/2.1.0 (Linux; U; Android 5.0; SM-G900F Build/LRX21T)",
    ]

    /// Starts listening, unless an attempt is already under way.
    func begin() {
        guard job == nil else { return }
        run += 1
        let mine = run
        job = Task { [weak self] in
            await self?.listen(mine)
            if self?.run == mine { self?.job = nil }
        }
    }

    private func listen(_ mine: Int) async {
        guard await requestMic() else {
            guard mine == run else { return }
            match = nil
            status = "Microphone access is off. Turn it on in Settings to recognise songs."
            phase = .failed
            return
        }
        guard mine == run else { return }
        match = nil
        phase = .listening

        do {
            let signature = try await captureSignature()
            guard mine == run else { return }
            // The microphone is done with; let it go while the lookup runs.
            stopEngine()
            phase = .finding
            let found = await lookup(signature)
            guard mine == run else { return }
            if let found {
                match = found
                phase = .found
            } else {
                phase = .notFound
            }
        } catch {
            guard mine == run else { return }
            stopEngine()
            status = "Couldn't listen: \(error.localizedDescription)"
            phase = .failed
        }
    }

    /// Stops whatever is under way and goes back to waiting for a tap. A result
    /// already on screen stays there.
    func stop() {
        run += 1
        job?.cancel()
        job = nil
        stopEngine()
        if phase == .listening || phase == .finding { phase = .idle }
    }

    // MARK: Capture

    private func captureSignature() async throws -> SHSignature {
        let session = AVAudioSession.sharedInstance()
        // Recording needs a category that permits input; restored in stopEngine().
        // `allowBluetooth` warns as renamed to `allowBluetoothHFP`, but that
        // spelling only exists from iOS 26 and we deploy to 17 — leave it.
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try session.setActive(true)

        let generator = SHSignatureGenerator()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // Convert to standard 44.1 kHz mono PCM. The mic's native format (often
        // 48 kHz) makes `append` throw, and swallowing that with `try?` left us
        // posting an empty signature — which always came back "no match".
        guard inputFormat.sampleRate > 0,
              let target = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let converter = AVAudioConverter(from: inputFormat, to: target)
        else { throw RecognitionError.microphoneUnavailable }

        let counter = AppendCounter()
        input.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { buffer, _ in
            let ratio = target.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

            var error: NSError?
            var handedOver = false
            converter.convert(to: converted, error: &error) { _, status in
                if handedOver {
                    status.pointee = .noDataNow
                    return nil
                }
                handedOver = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, converted.frameLength > 0 else { return }
            do {
                try generator.append(converted, at: nil)
                counter.bump()
            } catch {
                counter.fail(error)
            }
        }
        engine.prepare()
        try engine.start()

        try await Task.sleep(nanoseconds: UInt64(sampleSeconds * 1_000_000_000))

        guard counter.count > 0 else { throw counter.error ?? RecognitionError.noAudio }
        return generator.signature()
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        // Hand the session back to playback so music keeps working.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: Lookup

    private func lookup(_ signature: SHSignature) async -> Match? {
        let uri = "data:audio/vnd.shazam.sig;base64,"
            + signature.dataRepresentation.base64EncodedString()
        let millis = Int(Date().timeIntervalSince1970 * 1000)

        var comps = URLComponents(
            string: "https://amp.shazam.com/discovery/v5/en/US/android/-/tag/\(UUID().uuidString.lowercased())/\(UUID().uuidString.lowercased())")!
        comps.queryItems = [
            .init(name: "sync", value: "true"), .init(name: "webv3", value: "true"),
            .init(name: "sampling", value: "true"), .init(name: "connected", value: ""),
            .init(name: "shazamapiversion", value: "v3"), .init(name: "sharehub", value: "true"),
            .init(name: "video", value: "v3"),
        ]
        guard let url = comps.url else { return nil }

        let body: [String: Any] = [
            // Shazam wants a plausible fix; a random one keeps this from being a
            // location report, and the match doesn't depend on it.
            "geolocation": ["altitude": Double.random(in: 100...500),
                            "latitude": Double.random(in: -90...90),
                            "longitude": Double.random(in: -180...180)],
            "signature": ["samplems": Int(signature.duration * 1000),
                          "timestamp": millis, "uri": uri],
            "timestamp": millis,
            "timezone": TimeZone.current.identifier,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("en_US", forHTTPHeaderField: "Content-Language")
 // Shazam's tag endpoint expects a mobile client's shape; a default
        // URLSession agent gets much worse results.
        req.setValue(Self.userAgents.randomElement(), forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let track = json["track"] as? [String: Any]
        else { return nil }

        let images = track["images"] as? [String: Any]
        let art = (images?["coverarthq"] as? String) ?? (images?["coverart"] as? String)
        return Match(title: track["title"] as? String ?? "Unknown",
                     artist: track["subtitle"] as? String ?? "",
                     artworkURL: art.flatMap(URL.init(string:)))
    }

    private func requestMic() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }
}

/// Why a recognition attempt couldn't even start listening.
enum RecognitionError: LocalizedError {
    case microphoneUnavailable
    case noAudio

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: return "The microphone isn't available right now."
        case .noAudio: return "No audio reached the microphone."
        }
    }
}

/// Counts successful appends from the audio thread, so we can tell "heard
/// nothing" apart from "heard it but Shazam had no match".
final class AppendCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var firstError: Error?

    var count: Int { lock.withLock { value } }
    var error: Error? { lock.withLock { firstError } }

    func bump() { lock.withLock { value += 1 } }
    func fail(_ error: Error) { lock.withLock { if firstError == nil { firstError = error } } }
}
