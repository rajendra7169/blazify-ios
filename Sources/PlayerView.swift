import SwiftUI

/// The real Blazify-style player: album art, title/artist, a seekable progress
/// bar with elapsed/total times, and amber transport controls on a dark scaffold.
struct PlayerView: View {
    @ObservedObject var player: AudioPlayer

    // While dragging the slider, show the drag position instead of playback.
    @State private var dragValue: Double?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 8)

                // Album art
                AsyncImage(url: player.thumbnailURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Blaze.gradient
                        Image(systemName: "music.note")
                            .font(.system(size: 64))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: 300, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)

                // Title + artist
                VStack(spacing: 6) {
                    Text(player.title)
                        .font(.title2).bold()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(player.artist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal)

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
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 24)

                // Transport
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 76))
                        .foregroundStyle(Blaze.amber)
                }

                Spacer(minLength: 8)
            }
            .padding()
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
