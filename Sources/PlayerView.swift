import SwiftUI
import UIKit

/// Full-screen Blazify player: art, title/artist, seekable progress with times,
/// and amber transport (prev / play-pause / next) on a dark scaffold.
struct PlayerView: View {
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    @State private var dragValue: Double?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 22) {
                // Top bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3).foregroundStyle(.white)
                    }
                    Spacer()
                    Text("Now Playing")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Image(systemName: "chevron.down").opacity(0) // balance
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer(minLength: 0)

                // Album art
                AsyncImage(url: player.current?.thumbnailURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Blaze.gradient
                        Image(systemName: "music.note")
                            .font(.system(size: 64)).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: 300, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
                .overlay {
                    if player.isLoading {
                        ProgressView().tint(.white).scaleEffect(1.4)
                    }
                }

                // Title + artist
                VStack(spacing: 6) {
                    Text(player.current?.title ?? "")
                        .font(.title2).bold().foregroundStyle(.white).lineLimit(1)
                    Text(player.current?.artist ?? "")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                .padding(.horizontal)

                if let err = player.lastError {
                    VStack(spacing: 8) {
                        Text(err)
                            .font(.caption2).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        if let u = player.lastURL {
                            Button {
                                UIPasteboard.general.string = u
                            } label: {
                                Label("Copy stream URL", systemImage: "doc.on.doc")
                                    .font(.caption).foregroundStyle(Blaze.amber)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // Progress + times
                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { dragValue ?? player.progress },
                            set: { dragValue = $0 },
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if !editing, let v = dragValue {
                                player.seek(to: v)
                                dragValue = nil
                            }
                        },
                    )
                    .tint(Blaze.amber)

                    HStack {
                        Text(timeString((dragValue ?? player.progress) * player.duration))
                        Spacer()
                        Text(timeString(player.duration))
                    }
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 24)

                // Transport
                HStack(spacing: 44) {
                    Button { player.prev() } label: {
                        Image(systemName: "backward.fill").font(.title).foregroundStyle(.white)
                    }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 74)).foregroundStyle(Blaze.amber)
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.title).foregroundStyle(.white)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
