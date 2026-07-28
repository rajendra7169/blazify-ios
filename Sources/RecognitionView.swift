import SwiftUI
import ShazamKit
import AVFoundation

/// "What's playing?" — song recognition, the iOS counterpart to Blazify
/// Android's ShazamKit screen.
///
/// Same approach as the Android app: record a few seconds, turn it into a
/// Shazam *signature*, and POST that to Shazam's public tag endpoint. No
/// account, no API key, no entitlement — Android hand-ports the signature
/// algorithm; on iOS ShazamKit generates the identical format for us.
struct RecognitionView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var player: Player
    @StateObject private var recognizer = Recognizer()

    var body: some View {
        ZStack {
            palette.scaffold.ignoresSafeArea()

            VStack(spacing: 28) {
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

                pulsingMic

                Text(recognizer.status)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let match = recognizer.match {
                    result(match)
                }

                Spacer()

                if recognizer.isListening {
                    Button("Stop") { recognizer.stop() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.accent)
                } else {
                    Button {
                        Task { await recognizer.start() }
                    } label: {
                        Text(recognizer.match == nil ? "Listen" : "Listen again")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.onAccent)
                            .padding(.horizontal, 36).padding(.vertical, 14)
                            .background(palette.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer().frame(height: 40)
            }
        }
        .task { await recognizer.start() }
        .onDisappear { recognizer.stop() }
    }

    private var pulsingMic: some View {
        ZStack {
            Circle()
                .fill(palette.accent.opacity(0.16))
                .frame(width: recognizer.isListening ? 190 : 150,
                       height: recognizer.isListening ? 190 : 150)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                           value: recognizer.isListening)
            Circle()
                .fill(palette.accent)
                .frame(width: 110, height: 110)
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(palette.onAccent)
        }
    }

    private func result(_ match: Recognizer.Match) -> some View {
        VStack(spacing: 12) {
            RemoteImage(url: match.artworkURL) { palette.onSurface.opacity(0.06) }
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
                        player.showFullPlayer = true
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
        }
        .padding(.horizontal, 24)
    }
}

/// Records a few seconds, builds a Shazam signature locally, and asks Shazam's
/// public endpoint what it is — mirroring `Shazam.kt` on Android.
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

    @Published var isListening = false
    @Published var status = "Hold your phone towards the music"
    @Published var match: Match?

    private let engine = AVAudioEngine()
    private let sampleSeconds = 5.0

    func start() async {
        guard !isListening else { return }
        match = nil

        guard await requestMic() else {
            status = "Microphone access is off. Turn it on in Settings to recognise songs."
            return
        }

        isListening = true
        status = "Listening…"

        do {
            let signature = try await captureSignature()
            status = "Identifying…"
            if let found = await lookup(signature) {
                match = found
                status = "Got it"
            } else {
                status = "No match — try again with the music a little louder."
            }
        } catch {
            status = "Couldn't listen: \(error.localizedDescription)"
        }
        stopEngine()
        isListening = false
    }

    func stop() {
        stopEngine()
        isListening = false
        if match == nil { status = "Hold your phone towards the music" }
    }

    // MARK: Capture

    private func captureSignature() async throws -> SHSignature {
        let session = AVAudioSession.sharedInstance()
        // Recording needs a category that permits input; restored in stopEngine().
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try session.setActive(true)

        let generator = SHSignatureGenerator()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
            try? generator.append(buffer, at: time)
        }
        engine.prepare()
        try engine.start()

        try await Task.sleep(nanoseconds: UInt64(sampleSeconds * 1_000_000_000))
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
            string: "https://amp.shazam.com/discovery/v5/en/US/iphone/-/tag/\(UUID().uuidString.lowercased())/\(UUID().uuidString.lowercased())")!
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
