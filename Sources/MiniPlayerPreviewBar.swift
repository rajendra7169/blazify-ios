import SwiftUI

/// The mini-player drawn small, in whichever of Android's four designs is
/// selected. Shared by the Look & Feel preview so what you pick is what you get.
struct MiniPlayerPreviewBar: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    let design: MiniPlayerDesign
    let background: MiniPlayerBackground

    var body: some View {
        HStack(spacing: 7) {
            RemoteImage(url: player.current?.artURL(size: 120), size: 26) {
                palette.onSurface.opacity(0.12)
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: design == .flat ? 3 : 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(player.current?.title ?? "Song title")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(player.current?.artist ?? "Artist")
                    .font(.system(size: 5.5))
                    .foregroundStyle(ink.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            // ROUNDED is the only design with previous/next either side of play.
            if design == .rounded {
                Image(systemName: "backward.end.fill").font(.system(size: 8)).foregroundStyle(ink)
            }
            Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(ink)
            if design == .rounded {
                Image(systemName: "forward.end.fill").font(.system(size: 8)).foregroundStyle(ink)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(fill)
        .clipShape(shape)
        .overlay(alignment: .bottom) {
            // The flat bar keeps the thin progress line the original had.
            if design == .flat {
                GeometryReader { g in
                    Rectangle()
                        .fill(palette.accent)
                        .frame(width: g.size.width * max(player.progress, 0.05), height: 1.5)
                }
                .frame(height: 1.5)
            }
        }
        .shadow(color: design == .floating ? .black.opacity(0.35) : .clear, radius: 5, y: 2)
    }

    /// Text colour: dark designs sit on artwork, the flat one on the page.
    private var ink: Color {
        switch background {
        case .followTheme, .transparent: palette.onSurface
        default: design == .flat ? palette.onSurface : .white
        }
    }

    private var shape: AnyShape {
        switch design {
        case .flat: AnyShape(Rectangle())
        case .modern, .rounded: AnyShape(Capsule())
        case .floating: AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder private var fill: some View {
        if design == .flat {
            palette.surface
        } else {
            switch background {
            case .followTheme: palette.surface
            case .transparent: Color.clear
            case .pureBlack: Color.black
            case .blur:
                // Artwork behind a blur, the way the real bar does it.
                ZStack {
                    RemoteImage(url: player.current?.artURL(size: 120), size: 60) {
                        player.artColor
                    }
                    .blur(radius: 12)
                    Color.black.opacity(0.28)
                }
            case .gradient:
                LinearGradient(colors: [player.artColor, player.artColor.mixed(with: .black, 0.45)],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
    }
}
