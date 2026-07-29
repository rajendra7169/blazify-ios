import SwiftUI
import UIKit

/// "Player theme" gallery — a swipeable carousel of LIVE previews, each rendered
/// inside a phone frame, ported from PlayerDesignScreen.kt. Swiping only moves
/// the carousel; the design is persisted when you tap Apply.
struct PlayerDesignPicker: View {
    @ObservedObject var player: Player
    @AppStorage("playerDesign") private var activeID = PlayerDesign.classic.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var current: PlayerDesign?

    private var currentDesign: PlayerDesign { current ?? .classic }
    private var applied: Bool { currentDesign.rawValue == activeID }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            carousel

            Text(currentDesign.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 14)
                .padding(.bottom, 2)

            HStack(spacing: 6) {
                ForEach(PlayerDesign.allCases) { d in
                    let on = d == currentDesign
                    Circle()
                        .fill(on ? player.artColor : Color.white.opacity(0.35))
                        .frame(width: on ? 8 : 6, height: on ? 8 : 6)
                }
            }
            .padding(.top, 10)

            applyButton

            // The mini player follows you everywhere, including here.
            if player.hasTrack {
                MiniPlayerView(player: player) { dismiss() }
                    .padding(.bottom, 8)
            }
        }
        .background(Blaze.scaffold.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { current = PlayerDesign(rawValue: activeID) ?? .classic }
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            Text("Player theme")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    /// Neighbouring frames peek by design (62pt content margins, 16pt spacing).
    private var carousel: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width - 124
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(PlayerDesign.allCases) { design in
                        let focused = design == currentDesign
                        PhoneFrame {
                            DesignLivePreview(design: design, player: player)
                        }
                        // Slightly smaller than Android's 0.94/0.82 so the mini
                        // player fits underneath.
                        .frame(height: geo.size.height * (focused ? 0.90 : 0.78))
                        .frame(width: pageWidth, height: geo.size.height)
                        .id(design)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 62, for: .scrollContent)
            // Let the frame's glow spill past the scroll bounds instead of
            // being sliced off against the title bar and the name/dots below.
            .scrollClipDisabled()
        }
        .padding(.vertical, 26)
    }

    private var applyButton: some View {
        Button {
            activeID = currentDesign.rawValue
            dismiss()
        } label: {
            HStack(spacing: 8) {
                if applied {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                    Text("Using")
                } else {
                    Text("Apply")
                }
            }
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(applied ? .white.opacity(0.6) : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(applied ? AnyShapeStyle(Color.white.opacity(0.12))
                                : AnyShapeStyle(player.artColor))
            .clipShape(Capsule())
        }
        .disabled(applied)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

// MARK: - Phone frame

/// 9:19.3 body, 40pt outer / 33pt inner radius, 7pt bezel, white rim-glow.
struct PhoneFrame<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // GeometryReader keeps the frame's size independent of its contents
        // (the cassette once stretched it), and the explicit frame forces the
        // interior to exactly the screen size so nothing spills past the clip.
        GeometryReader { g in
            content()
                .frame(width: g.size.width, height: g.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 33, style: .continuous))
        }
            .overlay(alignment: .top) {
                // iPhone Dynamic Island (Android's frame draws a speaker slit here).
                Capsule()
                    .fill(.black)
                    .frame(width: 46, height: 13)
                    .padding(.top, 8)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x44454A), Color(hex: 0x26272B), Color(hex: 0x1A1B1E)],
                        startPoint: .top, endPoint: .bottom)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.10), .white.opacity(0.28)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1.5),
            )
            .aspectRatio(9.0 / 19.3, contentMode: .fit)
            .shadow(color: .white.opacity(0.22), radius: 18)
    }
}

// MARK: - Live preview

/// The real player, rendered small. Reads live state and its controls actually work.
struct DesignLivePreview: View {
    let design: PlayerDesign
    @ObservedObject var player: Player

    var body: some View {
        ZStack {
            if design != .fullArt {
                LinearGradient(colors: [player.artColor, player.artColor.opacity(0.45), .black],
                               startPoint: .top, endPoint: .bottom)
            }
            switch design {
            case .classic: ClassicPreview(player: player)
            case .ring: RingPreview(player: player)
            case .record: RecordPreview(player: player)
            case .cassette: CassettePreview(player: player)
            case .fullArt: FullArtPreview(player: player)
            }
        }
    }
}

// MARK: - Shared preview parts

private struct PreviewTitle: View {
    @ObservedObject var player: Player
    var shadow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(player.current?.title ?? "Song title")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white).lineLimit(1)
            Text(player.current?.artist ?? "Artist")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        }
        .shadow(color: shadow ? .black.opacity(0.75) : .clear, radius: 3, y: 2)
    }
}

private struct PreviewPill: View {
    let icon: String
    let bg: Color
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 12))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(bg)
            .clipShape(Circle())
    }
}

private struct PreviewSlider: View {
    @ObservedObject var player: Player
    var inactiveAlpha: Double = 0.22
    /// The preview follows the chosen slider style live, as Android's does.
    @ObservedObject private var look = LookFeel.shared

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { g in
                Group {
                    switch look.sliderStyle {
                    case .slim:
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(inactiveAlpha)).frame(height: 6)
                            Capsule().fill(player.artColor)
                                .frame(width: max(g.size.width * player.progress, 6), height: 6)
                        }
                    case .capsule:
                        CapsuleTrack(fraction: player.progress, active: player.artColor,
                                     label: capsuleLabel, compact: true)
                    case .wavy:
                        WavyTrack(fraction: player.progress, active: player.artColor,
                                  squiggly: look.squigglySlider, isPlaying: player.isPlaying)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                    player.seek(to: min(max(v.location.x / g.size.width, 0), 1))
                })
            }
            .frame(height: 16)

            HStack {
                Text(timeString(player.currentTime))
                Spacer()
                Text(player.duration > 0 ? timeString(player.duration) : "0:00")
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var capsuleLabel: String {
        guard player.duration > 0 else { return "0:00 / 0:00" }
        return "\(timeString(player.currentTime)) / \(timeString(player.duration))"
    }
}

private struct PreviewTransport: View {
    @ObservedObject var player: Player

    var body: some View {
        HStack {
            Spacer()
            Image(systemName: "shuffle").font(.system(size: 14)).foregroundStyle(.white)
            Spacer()
            Button { player.prev() } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 17)).foregroundStyle(.white)
            }
            Spacer()
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(player.artColor)
                    .clipShape(Circle())
            }
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 17)).foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "repeat").font(.system(size: 14)).foregroundStyle(.white)
            Spacer()
        }
    }
}

private struct PreviewFavorite: View {
    @ObservedObject var player: Player

    var body: some View {
        Button { player.toggleFavorite() } label: {
            Image(systemName: player.isCurrentFavorite ? "heart.fill" : "heart")
                .font(.system(size: 15))
                .foregroundStyle(player.isCurrentFavorite ? .red : .white)
        }
    }
}

private struct PreviewQueuePeek: View {
    var body: some View {
        HStack {
            ForEach([("list.bullet", "Queue"), ("moon.zzz", "Sleep timer"),
                     ("text.alignleft", "Lyrics")], id: \.0) { icon, label in
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.system(size: 11))
                    Text(label).font(.system(size: 9)).lineLimit(1)
                }
                .foregroundStyle(.white)
                Spacer()
            }
        }
        .padding(.top, 4)
    }
}

/// Title row shared by CLASSIC / RECORD / FULL_ART.
private struct PreviewMetaRow: View {
    @ObservedObject var player: Player
    var pillAlpha: Double = 0.14
    var shadow = false

    var body: some View {
        HStack(spacing: 0) {
            PreviewTitle(player: player, shadow: shadow)
            Spacer(minLength: 6)
            PreviewFavorite(player: player)
            Spacer().frame(width: 10)
            PreviewPill(icon: "paintpalette", bg: .white.opacity(pillAlpha), tint: .white)
            Spacer().frame(width: 8)
            PreviewPill(icon: "ellipsis", bg: .white.opacity(pillAlpha), tint: .white)
        }
    }
}

// MARK: - Per-design previews

private struct ClassicPreview: View {
    @ObservedObject var player: Player

    var body: some View {
        VStack(spacing: 0) {
            Text("Now Playing").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            Spacer()
            GeometryReader { g in
                RemoteImage(url: player.current?.artURL(size: 480)) { ArtPlaceholder() }
                    .frame(width: g.size.width * 0.82, height: g.size.width * 0.82)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .frame(width: g.size.width, alignment: .center)
            }
            .aspectRatio(1.22, contentMode: .fit)
            Spacer().frame(height: 16)
            PreviewMetaRow(player: player)
            Spacer().frame(height: 12)
            PreviewSlider(player: player)
            Spacer()
            PreviewTransport(player: player)
            Spacer()
            PreviewQueuePeek()
        }
        .padding(16)
        .padding(.top, 20)   // clear the Dynamic Island pill
    }
}

private struct RingPreview: View {
    @ObservedObject var player: Player

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chevron.down").font(.system(size: 17))
                Text("Now Playing")
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                Image(systemName: "paintpalette").font(.system(size: 15))
            }
            .foregroundStyle(.white)

            Spacer()
            GeometryReader { g in
                let side = g.size.width * 0.66
                SeekableAlbumRing(
                    artURL: player.current?.artURL(size: 480),
                    progress: player.progress,
                    ringColor: player.artColor,
                    trackColor: .white.opacity(0.20),
                    thumbColor: player.artColor,
                    stroke: 5, artPadding: 9,
                ) { player.seek(to: $0) }
                .frame(width: side, height: side)
                .frame(width: g.size.width, height: g.size.height, alignment: .center)
            }
            .aspectRatio(1.4, contentMode: .fit)
            Spacer()

            HStack {
                Image(systemName: "list.bullet").font(.system(size: 15)).foregroundStyle(.white)
                Spacer()
                PreviewFavorite(player: player)
            }
            .padding(.horizontal, 4)

            Spacer().frame(height: 6)
            PreviewSlider(player: player)
            Spacer().frame(height: 8)
            PreviewTransport(player: player)
            Spacer().frame(height: 8)

            HStack {
                Image(systemName: "moon.zzz").font(.system(size: 14))
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 14))
            }
            .foregroundStyle(.white)

            Spacer().frame(height: 8)

            // Lyrics card — bleeds to the bottom edge (no bottom padding).
            VStack(spacing: 0) {
                HStack {
                    Text("Show Lyrics").font(.system(size: 11, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.up").font(.system(size: 12))
                }
                .foregroundStyle(.white)
                Spacer().frame(height: 6)
                Text("In the stillness of the night")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                Spacer().frame(height: 2)
                Text("I feel the weight, the empty sight")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(player.artColor).lineLimit(1)
                Spacer().frame(height: 2)
                Text("Whispers in my mind, they call")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Color.black.opacity(0.45))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        }
        .padding(.horizontal, 14)
        .padding(.top, 34)   // clear the Dynamic Island pill
    }
}

private struct RecordPreview: View {
    @ObservedObject var player: Player

    var body: some View {
        VStack(spacing: 0) {
            Text("Now Playing").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            Spacer()
            GeometryReader { g in
                VinylTurntableView(
                    artURL: player.current?.artURL(size: 480),
                    isPlaying: player.isPlaying,
                    progress: player.progress,
                    fallback: Blaze.gradient,
                )
                .frame(width: g.size.width * 0.94, height: g.size.width * 0.94)
                .frame(width: g.size.width, alignment: .center)
            }
            .aspectRatio(1.05, contentMode: .fit)
            Spacer()
            PreviewMetaRow(player: player)
            Spacer().frame(height: 12)
            PreviewSlider(player: player)
            Spacer().frame(height: 10)
            PreviewTransport(player: player)
            Spacer().frame(height: 10)
            PreviewQueuePeek()
        }
        .padding(16)
        .padding(.top, 20)   // clear the Dynamic Island pill
    }
}

private struct CassettePreview: View {
    @ObservedObject var player: Player

    private let cream = Color(hex: 0xF2E7D0)
    private let ink = Color(hex: 0x3A2F24)

    var body: some View {
        VStack(spacing: 0) {
            Text("Now Playing").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            Spacer()
            CassetteTapeView(
                isPlaying: player.isPlaying,
                progress: player.progress,
                accent: player.artColor,
                artURL: player.current?.artURL(size: 300),
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            Spacer()

            VStack(spacing: 3) {
                Text(player.current?.title ?? "Song title")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(player.current?.artist ?? "Artist")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }

            Spacer().frame(height: 8)

            // Waveform card — 24 bars in the gallery (36 in the real player).
            HStack(spacing: 8) {
                Canvas { ctx, size in
                    let n = 24
                    let gap = size.width / CGFloat(n)
                    let barW = gap * 0.55
                    for i in 0..<n {
                        let wave = abs(sin(Double(i) * 1.7) * 0.5 + sin(Double(i) * 0.53 + 1.3) * 0.5)
                        let barH = size.height * min(max(0.30 + 0.65 * CGFloat(wave), 0.15), 1)
                        let played = (Double(i) + 0.5) / Double(n) <= player.progress
                        ctx.fill(
                            Path(roundedRect: CGRect(x: gap * CGFloat(i) + (gap - barW) / 2,
                                                     y: (size.height - barH) / 2,
                                                     width: barW, height: barH),
                                 cornerRadius: barW / 2),
                            with: .color(played ? player.artColor : ink.opacity(0.25)))
                    }
                }
                .frame(height: 22)
                Image(systemName: "heart").font(.system(size: 13)).foregroundStyle(ink)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(cream)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer().frame(height: 10)

            // Decorative retro keys.
            HStack(spacing: 8) {
                key(width: 44, bg: cream) {
                    Image(systemName: "backward.end.fill").font(.system(size: 14)).foregroundStyle(ink)
                }
                key(width: 52, height: 38, bg: player.artColor) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15)).foregroundStyle(.white)
                }
                key(width: 44, bg: cream) {
                    Image(systemName: "forward.end.fill").font(.system(size: 14)).foregroundStyle(ink)
                }
            }

            Spacer().frame(height: 10)

            HStack(spacing: 0) {
                segment("text.alignleft", bg: player.artColor, tint: .white)
                segment("list.bullet", bg: Color(hex: 0x2A241E), tint: cream)
                segment("moon.zzz", bg: Color(hex: 0x2A241E), tint: cream)
                segment("paintpalette", bg: Color(hex: 0x2A241E), tint: cream)
                segment("ellipsis", bg: Color(hex: 0x2A241E), tint: cream)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .padding(.top, 20)
    }

    private func key<C: View>(width: CGFloat, height: CGFloat = 34, bg: Color,
                              @ViewBuilder content: () -> C) -> some View {
        content()
            .frame(width: width, height: height)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func segment(_ icon: String, bg: Color, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12))
            .foregroundStyle(tint)
            .frame(width: 40, height: 34)
            .background(bg)
    }
}

private struct FullArtPreview: View {
    @ObservedObject var player: Player

    var body: some View {
        ZStack {
            // Explicit size: RemoteImage fills to its natural size otherwise and
            // would burst out of the phone frame.
            GeometryReader { g in
                RemoteImage(url: player.current?.artURL(size: 720)) { ArtPlaceholder() }
                    .frame(width: g.size.width, height: g.size.height)
                    .clipped()
            }

            LinearGradient(stops: [
                .init(color: .black.opacity(0.30), location: 0.0),
                .init(color: .clear, location: 0.35),
                .init(color: .black.opacity(0.55), location: 0.65),
                .init(color: .black.opacity(0.92), location: 1.0),
            ], startPoint: .top, endPoint: .bottom)

            VStack {
                Text("Now Playing")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.75), radius: 3, y: 2)
                    .padding(.top, 30)   // clear the Dynamic Island pill
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()
                PreviewMetaRow(player: player, pillAlpha: 0.18, shadow: true)
                Spacer().frame(height: 10)
                PreviewSlider(player: player, inactiveAlpha: 0.25)
                Spacer().frame(height: 10)
                PreviewTransport(player: player)
                Spacer().frame(height: 12)
                PreviewQueuePeek()
            }
            .padding(16)
        }
    }
}
