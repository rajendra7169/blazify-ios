import SwiftUI

/// Shared placeholder for missing art.
struct ArtPlaceholder: View {
    var body: some View {
        ZStack {
            Blaze.gradient
            Image(systemName: "music.note")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// CLASSIC — square rounded album art.
struct SquareArtwork: View {
    @ObservedObject var player: Player
    let side: CGFloat

    var body: some View {
        RemoteImage(url: player.current?.artURL(size: 1080)) { ArtPlaceholder() }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
    }
}
