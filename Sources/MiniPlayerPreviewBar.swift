import SwiftUI

/// The mini-player drawn small for pickers and previews — a faithful copy of
/// the mini section of the phone preview: art shape, trailing
/// controls, card shape and background all switch with the design.
struct MiniPlayerPreviewBar: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    let design: MiniPlayerDesign
    let background: MiniPlayerBackground

    private var isFlat: Bool { design == .flat }
    private var isFloating: Bool { design == .floating }

 /// Ink per background, as the preview picks it.
    private var onMini: Color {
        switch background {
        case .gradient: return palette.onAccent
        case .pureBlack: return .white
        default: return palette.onSurface
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            RemoteImage(url: player.current?.artURL(size: 120), size: 23) {
                onMini.opacity(0.85)
            }
            .frame(width: 23, height: 23)
            .clipShape(isFlat || isFloating
                       ? AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                       : AnyShape(Circle()))

            Spacer().frame(width: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.current?.title ?? "Song title")
                    .font(.system(size: 7, weight: .bold)).lineLimit(1)
                Text(player.current?.artist ?? "Artist")
                    .font(.system(size: 5.5)).opacity(0.7).lineLimit(1)
            }
            .foregroundStyle(onMini)
            Spacer(minLength: 5)

            switch design {
            case .rounded:
                // prev · play in a filled circle · next.
                HStack(spacing: 2) {
                    Image(systemName: "backward.end.fill").font(.system(size: 8))
                        .foregroundStyle(onMini)
                    Circle().fill(onMini)
                        .frame(width: 15, height: 15)
                        .overlay(Image(systemName: "play.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(background == .gradient ? palette.accent
                                                                     : palette.surface))
                    Image(systemName: "forward.end.fill").font(.system(size: 8))
                        .foregroundStyle(onMini)
                }
            case .flat:
                Image(systemName: "heart").font(.system(size: 9)).foregroundStyle(onMini)
            default:
                HStack(spacing: 5) {
                    Image(systemName: "text.badge.plus").font(.system(size: 9))
                    Image(systemName: "heart").font(.system(size: 9))
                }
                .foregroundStyle(onMini.opacity(0.9))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(fill)
        .clipShape(shape)
        .shadow(color: isFloating ? .black.opacity(0.3) : .clear, radius: 4, y: 2)
 // Floating rides slightly inset, as the 0.94-width card does.
        .padding(.horizontal, isFloating ? 8 : 0)
    }

    private var shape: AnyShape {
        if isFlat { return AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) }
        if isFloating { return AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
        return AnyShape(Capsule())
    }

    @ViewBuilder private var fill: some View {
        switch background {
        case .gradient:
            LinearGradient(colors: [palette.accent, palette.accent.opacity(0.72)],
                           startPoint: .leading, endPoint: .trailing)
        case .pureBlack: Color.black
        default: palette.surfaceHigh
        }
    }
}
