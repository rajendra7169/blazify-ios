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

/// RING — circular art wrapped by a seekable-looking progress ring.
struct RingArtwork: View {
    @ObservedObject var player: Player
    let side: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.001, player.progress))
                .stroke(player.artColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            RemoteImage(url: player.current?.artURL(size: 1080)) { ArtPlaceholder() }
                .clipShape(Circle())
                .padding(18)
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}

/// RECORD — spinning vinyl with the art as the centre label.
struct RecordArtwork: View {
    @ObservedObject var player: Player
    let side: CGFloat
    @State private var angle = 0.0

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0x0E0E10))
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .padding(CGFloat(22 + i * 16))
            }
            RemoteImage(url: player.current?.artURL(size: 720)) { ArtPlaceholder() }
                .clipShape(Circle())
                .frame(width: side * 0.46, height: side * 0.46)
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: side * 0.46, height: side * 0.46)
            Circle().fill(Color.black).frame(width: 12, height: 12)
        }
        .frame(width: side, height: side)
        .rotationEffect(.degrees(angle))
        .shadow(color: .black.opacity(0.5), radius: 22, y: 12)
        .onAppear {
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { angle = 360 }
        }
    }
}

/// CASSETTE — retro tape with the art on the label and two spinning reels.
struct CassetteArtwork: View {
    @ObservedObject var player: Player
    let side: CGFloat
    @State private var reel = 0.0

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(LinearGradient(colors: [Color(hex: 0x2B2B30), Color(hex: 0x141416)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: side, height: side * 0.66)
            .overlay {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        RemoteImage(url: player.current?.artURL(size: 300)) { ArtPlaceholder() }
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(player.current?.title ?? "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 44) {
                        reelView
                        reelView
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(12)
            }
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { reel = 360 }
            }
    }

    private var reelView: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.3), lineWidth: 3).frame(width: 42, height: 42)
            ForEach(0..<6, id: \.self) { i in
                Capsule().fill(Color.white.opacity(0.25))
                    .frame(width: 3, height: 11)
                    .offset(y: -9)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            Circle().fill(Color.white.opacity(0.5)).frame(width: 10, height: 10)
        }
        .rotationEffect(.degrees(reel))
    }
}
