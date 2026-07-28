import SwiftUI

/// The theme preview: a miniature Home — greeting card, search pill, chips and
/// a rail — painted with the palette currently selected, so switching mode or
/// colour repaints it live.
struct LookFeelThemePreview: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var look = LookFeel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 22)

            HStack(spacing: 5) {
                Circle().fill(palette.onSurface.opacity(0.25)).frame(width: 11, height: 11)
                Spacer()
                Text("Blazify")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(palette.onSurface)
                Spacer()
                Circle().fill(palette.onSurface.opacity(0.25)).frame(width: 11, height: 11)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            if look.showHomeGreeting {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.heroGradient)
                    .frame(height: 46)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Good Evening")
                                .font(.system(size: 8, weight: .bold))
                            Text("Enjoy the music")
                                .font(.system(size: 6))
                                .opacity(0.85)
                        }
                        .foregroundStyle(.white)
                        .padding(.leading, 9)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 7)
            }

            if look.showHomeSearchBar {
                Capsule()
                    .fill(palette.onSurface.opacity(0.10))
                    .frame(height: 17)
                    .overlay(alignment: .leading) {
                        Text("Search songs, albums…")
                            .font(.system(size: 6))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .padding(.leading, 9)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 7)
            }

            HStack(spacing: 4) {
                ForEach(["All", "Workout", "Relax"], id: \.self) { chip in
                    let active = chip == "All"
                    Text(chip)
                        .font(.system(size: 5.5, weight: .semibold))
                        .foregroundStyle(active ? palette.onAccent : palette.onSurface)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(active ? AnyShapeStyle(palette.accent)
                                           : AnyShapeStyle(palette.onSurface.opacity(0.08)))
                        .clipShape(Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Text("Listen again")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 10)
                .padding(.bottom, 5)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(palette.onSurface.opacity(0.12))
                            .frame(width: cardSide, height: cardSide)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.onSurface.opacity(0.22))
                            .frame(width: cardSide * 0.8, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.onSurface.opacity(0.12))
                            .frame(width: cardSide * 0.55, height: 3)
                    }
                    .opacity(i == 2 ? 0.5 : 1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
            LookFeelNavBarPreview()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.scaffold)
    }

    /// Grid size actually changes the card width, so the preview shows it.
    private var cardSide: CGFloat { look.gridItemSize == .small ? 40 : 52 }
}

/// The bottom bar as configured — style and slimness both visible.
struct LookFeelNavBarPreview: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var look = LookFeel.shared

    private let tabs = ["house.fill", "safari.fill", "sparkles", "books.vertical.fill"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, icon in
                let active = i == 0
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(active ? activeInk : palette.onSurfaceVariant)
                    if !look.slimNavBar {
                        Text(" ")
                            .font(.system(size: 5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(active ? activeInk : palette.onSurfaceVariant)
                                    .frame(width: 12, height: 2.5),
                            )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, look.slimNavBar ? 5 : 7)
                .background(activeBackground(active))
                .overlay(alignment: .bottom) {
                    if look.navBarStyle == .underline, active {
                        Capsule().fill(palette.accent).frame(width: 18, height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, look.slimNavBar ? 3 : 5)
        .background(palette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.separator).frame(height: 0.5)
        }
    }

    private var activeInk: Color {
        switch look.navBarStyle {
        case .pill, .gradient: palette.onAccent
        case .underline, .outlined: palette.accent
        }
    }

    @ViewBuilder
    private func activeBackground(_ active: Bool) -> some View {
        if active {
            switch look.navBarStyle {
            case .pill:
                Capsule().fill(palette.accent)
            case .gradient:
                Capsule().fill(LinearGradient(
                    colors: [palette.accent, palette.accent.mixed(with: .black, 0.3)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            case .outlined:
                Capsule().strokeBorder(palette.accent, lineWidth: 1.2)
            case .underline:
                Color.clear
            }
        } else {
            Color.clear
        }
    }
}

/// The player preview: whichever design is selected, drawn small.
struct LookFeelPlayerPreview: View {
    @ObservedObject var player: Player
    @AppStorage("playerDesign") private var designRaw = PlayerDesign.classic.rawValue
    @ObservedObject private var look = LookFeel.shared

    private var design: PlayerDesign { PlayerDesign(rawValue: designRaw) ?? .classic }

    var body: some View {
        ZStack {
            LinearGradient(colors: [player.artColor.mixed(with: .black, 0.45), .black],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                Spacer().frame(height: 26)
                artwork
                Spacer().frame(height: 12)

                Text(player.current?.title ?? "Song title")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(player.current?.artist ?? "Artist")
                    .font(.system(size: 7))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                Spacer().frame(height: 10)
                LookFeelSliderPreview(style: look.sliderStyle, squiggly: look.squigglySlider,
                                      tint: player.artColor)
                    .padding(.horizontal, 18)

                Spacer().frame(height: 12)
                HStack(spacing: 16) {
                    Image(systemName: "backward.end.fill").font(.system(size: 11))
                    Image(systemName: "play.fill")
                        .font(.system(size: 13))
                        .frame(width: 30, height: 30)
                        .background(player.artColor)
                        .clipShape(Circle())
                    Image(systemName: "forward.end.fill").font(.system(size: 11))
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder private var artwork: some View {
        let art = player.current?.artURL(size: 360)
        switch design {
        case .ring:
            RemoteImage(url: art, size: 110) { Color.white.opacity(0.1) }
                .clipShape(Circle())
                .padding(8)
                .overlay(Circle().strokeBorder(player.artColor, lineWidth: 3))
                .frame(width: 118, height: 118)
        case .fullArt:
            RemoteImage(url: art, size: 160) { Color.white.opacity(0.1) }
                .frame(height: 140)
                .clipped()
        case .record:
            RemoteImage(url: art, size: 110) { Color.white.opacity(0.1) }
                .clipShape(Circle())
                .frame(width: 112, height: 112)
                .overlay(Circle().fill(.black).frame(width: 16, height: 16))
        case .cassette:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .frame(width: 140, height: 92)
                .overlay {
                    HStack(spacing: 18) {
                        Circle().fill(.white.opacity(0.25)).frame(width: 24, height: 24)
                        Circle().fill(.white.opacity(0.25)).frame(width: 24, height: 24)
                    }
                }
        case .classic:
            RemoteImage(url: art, size: 130) { Color.white.opacity(0.1) }
                .frame(width: 118, height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// The seek bar in each of its three styles, used by the player preview.
struct LookFeelSliderPreview: View {
    let style: SliderStyle
    let squiggly: Bool
    let tint: Color
    var progress: Double = 0.42

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                switch style {
                case .capsule:
                    Capsule().fill(.white.opacity(0.24)).frame(height: 5)
                    Capsule().fill(tint).frame(width: max(w * progress, 5), height: 5)
                case .slim:
                    Capsule().fill(.white.opacity(0.24)).frame(height: 3)
                    Capsule().fill(tint).frame(width: max(w * progress, 3), height: 3)
                case .wavy:
                    Capsule().fill(.white.opacity(0.24)).frame(height: 2)
                    Wave(amplitude: squiggly ? 3.5 : 2, wavelength: squiggly ? 9 : 16)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: max(w * progress, 6), height: 10)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 12)
    }
}

/// A sine used by the wavy/squiggly slider — squiggly is just tighter and taller.
struct Wave: Shape {
    var amplitude: CGFloat
    var wavelength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY
        path.move(to: CGPoint(x: 0, y: mid))
        var x: CGFloat = 0
        while x <= rect.width {
            let y = mid + amplitude * sin(x / wavelength * 2 * .pi)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 1
        }
        return path
    }
}

/// The lyrics preview — alignment follows the position setting, as Android's does.
struct LookFeelLyricsPreview: View {
    @ObservedObject var player: Player
    let position: LyricsPosition

    var body: some View {
        VStack(alignment: position.alignment, spacing: 0) {
            Spacer().frame(height: 26)

            HStack(spacing: 3) {
                Image(systemName: "character.bubble").font(.system(size: 6))
                Text("Language").font(.system(size: 5.5))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.white.opacity(0.16))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: position.alignment, spacing: 14) {
                Spacer(minLength: 0)
                line("Baatein teri,\nraatein-saugaate", opacity: 0.30, size: 9)
                line("Tere bina jeena\nseekh liya maine", opacity: 1, size: 11, bold: true)
                line("Phir bhi teri yaad\naati hai", opacity: 0.30, size: 9)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.frameAlignment)
            .padding(.horizontal, 14)

            HStack(spacing: 6) {
                RemoteImage(url: player.current?.artURL(size: 120), size: 22) {
                    Color.white.opacity(0.15)
                }
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.current?.title ?? "Song title")
                        .font(.system(size: 6.5, weight: .semibold)).lineLimit(1)
                    Text(player.current?.artist ?? "Artist")
                        .font(.system(size: 5.5)).opacity(0.7).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "ellipsis").font(.system(size: 7))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [player.artColor.mixed(with: .black, 0.62), .black],
                           startPoint: .top, endPoint: .bottom),
        )
    }

    private func line(_ text: String, opacity: Double, size: CGFloat, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: size, weight: bold ? .bold : .regular))
            .foregroundStyle(.white.opacity(opacity))
            .multilineTextAlignment(position.textAlignment)
            .frame(maxWidth: .infinity, alignment: position.frameAlignment)
    }
}

/// The mini-player preview: the chosen design over a sample page.
struct LookFeelMiniPreview: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var look = LookFeel.shared

    var body: some View {
        VStack(spacing: 0) {
            LookFeelThemePreviewBody()
            Spacer(minLength: 0)
            MiniPlayerPreviewBar(player: player,
                                 design: look.miniPlayerDesign,
                                 background: look.miniPlayerBackground)
                .padding(.horizontal, look.miniPlayerDesign == .flat ? 0 : 8)
                .padding(.bottom, look.miniPlayerDesign == .flat ? 0 : 6)
            LookFeelNavBarPreview()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.scaffold)
    }
}

/// Just the content half of the theme preview, reused by the mini-player tab.
struct LookFeelThemePreviewBody: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Spacer().frame(height: 24)
            Text("Listen again")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 10)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(palette.onSurface.opacity(0.12))
                        .frame(width: 40, height: 40)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
        }
    }
}
