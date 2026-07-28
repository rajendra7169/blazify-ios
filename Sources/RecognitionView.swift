import SwiftUI
import ShazamKit
import AVFoundation

/// "What's playing?" — song recognition, the iOS counterpart to Blazify
/// Android's ShazamKit screen.
///
/// iOS has ShazamKit built in, so this listens on the mic and matches locally
/// against Shazam's catalog — no third-party service and no API key of ours.
struct RecognitionView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var player: Player
    @StateObject private var engine = Recognizer()

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

                Text(engine.status)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let match = engine.match {
                    result(match)
                }

                Spacer()

                if engine.isListening {
                    Button("Stop") { engine.stop() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.accent)
                } else {
                    Button {
                        Task { await engine.start() }
                    } label: {
                        Text(engine.match == nil ? "Listen" : "Listen again")
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
        .task { await engine.start() }
        .onDisappear { engine.stop() }
    }

    private var pulsingMic: some View {
        ZStack {
            Circle()
                .fill(palette.accent.opacity(0.16))
                .frame(width: engine.isListening ? 190 : 150,
                       height: engine.isListening ? 190 : 150)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                           value: engine.isListening)
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

/// Wraps ShazamKit's managed session, which does its own mic capture.
@MainActor
final class Recognizer: ObservableObject {
    struct Match {
        let title: String
        let artist: String
        let artworkURL: URL?
    }

    @Published var isListening = false
    @Published var status = "Tap Listen and hold your phone to the music"
    @Published var match: Match?

    private let session = SHManagedSession()

    func start() async {
        guard !isListening else { return }
        match = nil

        guard await requestMic() else {
            status = "Microphone access is off. Enable it in Settings to recognise songs."
            return
        }

        isListening = true
        status = "Listening…"

        let result = await session.result()
        isListening = false

        switch result {
        case .match(let shazam):
            guard let item = shazam.mediaItems.first else {
                status = "Couldn't identify that one. Try again."
                return
            }
            match = Match(title: item.title ?? "Unknown",
                          artist: item.artist ?? "",
                          artworkURL: item.artworkURL)
            status = "Found it"
        case .noMatch:
            status = "No match — try again with the music a bit louder."
        case .error(let error, _):
            status = error.localizedDescription
        }
    }

    func stop() {
        session.cancel()
        isListening = false
        if match == nil { status = "Tap Listen and hold your phone to the music" }
    }

    private func requestMic() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }
}
