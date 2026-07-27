import SwiftUI

/// The bar above the content: current track + play/pause. Tap to open the full player.
struct MiniPlayerView: View {
    @ObservedObject var player: Player

    var body: some View {
        if let track = player.current {
            HStack(spacing: 12) {
                AsyncImage(url: track.thumbnailURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Blaze.gradient
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.white).lineLimit(1)
                    Text(track.artist)
                        .font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)),
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture { player.showFullPlayer = true }
        }
    }
}
