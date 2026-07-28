import SwiftUI

/// The palette button's page: swipe through the player designs, each shown live
/// inside an iPhone frame; tap to apply. Matches Android's design chooser.
struct PlayerDesignPicker: View {
    @ObservedObject var player: Player
    @AppStorage("playerDesign") private var designRaw = PlayerDesign.classic.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PlayerDesign = .classic

    var body: some View {
        ZStack {
            LinearGradient(colors: [player.artColor.opacity(0.5), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                    }
                    Spacer()
                    Text("Player design").font(.system(size: 17, weight: .bold))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)

                TabView(selection: $selection) {
                    ForEach(PlayerDesign.allCases) { design in
                        VStack(spacing: 18) {
                            PhoneFrame { DesignPreview(design: design, player: player) }
                            VStack(spacing: 4) {
                                Text(design.title).font(.system(size: 20, weight: .bold))
                                Text(design.subtitle)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.bottom, 42)
                        .tag(design)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    designRaw = selection.rawValue
                    dismiss()
                } label: {
                    Text(selection.rawValue == designRaw ? "Selected" : "Use this design")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(selection.rawValue == designRaw
                                    ? AnyShapeStyle(Color.white.opacity(0.15))
                                    : AnyShapeStyle(Blaze.gradient))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 14)
            }
            .foregroundStyle(.white)
        }
        .onAppear { selection = PlayerDesign(rawValue: designRaw) ?? .classic }
        .preferredColorScheme(.dark)
    }
}

/// A simple iPhone bezel wrapper.
struct PhoneFrame<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: 208, height: 430)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(alignment: .top) {
                Capsule().fill(Color.black).frame(width: 58, height: 17).padding(.top, 9)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 12),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1),
            )
    }
}

/// A miniature, live preview of one design (uses the current song's art).
struct DesignPreview: View {
    let design: PlayerDesign
    @ObservedObject var player: Player

    var body: some View {
        ZStack {
            LinearGradient(colors: [player.artColor, player.artColor.opacity(0.4), .black],
                           startPoint: .top, endPoint: .bottom)

            if design == .fullArt {
                RemoteImage(url: player.current?.artURL(size: 720)) { ArtPlaceholder() }
                    .frame(width: 208, height: 430).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.85)],
                               startPoint: .center, endPoint: .bottom)
            }

            VStack(spacing: 8) {
                Text("Now Playing").font(.system(size: 9, weight: .semibold)).opacity(0.9)
                Spacer(minLength: 0)
                if design != .fullArt { stage }
                Spacer(minLength: 0)
                Text(player.current?.title ?? "Song title")
                    .font(.system(size: 11, weight: .bold)).lineLimit(1)
                Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Capsule().fill(player.artColor).frame(width: g.size.width * player.progress)
                        }
                        .frame(height: 4)
                    }
                    .padding(.horizontal, 6)
                HStack(spacing: 14) {
                    Image(systemName: "shuffle").font(.system(size: 9))
                    Image(systemName: "backward.end.fill").font(.system(size: 11))
                    Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(.black)
                        .frame(width: 26, height: 26).background(Color.white).clipShape(Circle())
                    Image(systemName: "forward.end.fill").font(.system(size: 11))
                    Image(systemName: "repeat").font(.system(size: 9))
                }
            }
            .padding(12)
            .foregroundStyle(.white)
        }
        .frame(width: 208, height: 430)
    }

    @ViewBuilder private var stage: some View {
        switch design {
        case .classic: SquareArtwork(player: player, side: 128)
        case .ring: RingArtwork(player: player, side: 132)
        case .record: RecordArtwork(player: player, side: 132)
        case .cassette: CassetteArtwork(player: player, side: 150)
        case .fullArt: EmptyView()
        }
    }
}
