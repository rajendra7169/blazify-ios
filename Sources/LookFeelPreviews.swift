import SwiftUI

/// Faithful port of Android's `ThemePhonePreview`: a miniature of the real home
/// — header with the actual logo, greeting card with the hero spilling out of
/// its top, search pill with mic, mood chips, Quick picks rows, the REAL
/// mini-player (art + title from what's playing, drawn in the chosen design and
/// background) and the nav bar in the chosen style. Used by the Theme, Mini and
/// Home tabs, exactly as on Android.
struct LookFeelThemePreview: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var look = LookFeel.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer().frame(height: 6)

            if look.showHomeGreeting {
                greetingCard
                Spacer().frame(height: 9)
            }
            if look.showHomeSearchBar {
                searchPill
                Spacer().frame(height: 8)
            }

            moodChips
            Spacer().frame(height: 9)
            quickPicksHeader
            Spacer().frame(height: 7)
            songRows

            Spacer(minLength: 0)
            miniPlayer
            Spacer().frame(height: look.slimNavBar ? 7 : 9)
            navBar
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        // Room for the frame's notch, which the Kotlin frame draws above this.
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.scaffold)
    }

    // MARK: Header — person · logo + wordmark · settings

    private var header: some View {
        HStack {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 12))
                .foregroundStyle(palette.onSurface.opacity(0.75))
            Spacer()
            HStack(spacing: 3) {
                Image(bundleImage: palette.dark ? "blaze_logo_white" : "blaze_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                Text("Blazify")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.onSurface)
            }
            Spacer()
            Image(systemName: "gearshape")
                .font(.system(size: 12))
                .foregroundStyle(palette.onSurface.opacity(0.75))
        }
    }

    // MARK: Greeting card — hero spills out of the top, like the real home

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good\nMorning 🌅"
        case 12..<17: return "Good\nAfternoon ☀️"
        case 17..<21: return "Good\nEvening 🌆"
        default: return "Good\nNight 🌙"
        }
    }

    private var greetingCard: some View {
        // The card alone sets the height. The hero is an OVERLAY, not a ZStack
        // sibling: at 92 tall it made the stack 92 too, and framing that back to
        // 68 centred it — which dropped the card 12pt onto the search field.
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(
                colors: [palette.accent,
                         palette.accent.mixed(with: .black, palette.dark ? 0.30 : 0.20)],
                startPoint: .leading, endPoint: .trailing))
            .frame(height: 68)
            .overlay(alignment: .bottomTrailing) {
                // Taller than the card, so it spills out of the top the way the
                // real home's hero does — an overlay never resizes its parent.
                Image(bundleImage: palette.dark ? "blaze_home_dark" : "blaze_home_light")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 78, height: 92)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.system(size: 8.5, weight: .bold))
                        .lineSpacing(0)
                    Text("Music Lover")
                        .font(.system(size: 7.5, weight: .bold))
                        .opacity(0.95)
                    Text("Enjoy the music 🎵")
                        .font(.system(size: 5.5, weight: .medium))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.leading, 11)
            }
    }

    // MARK: Search pill — icon · placeholder · mic

    private var searchPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 9))
            Text("Search songs, artists…").font(.system(size: 7))
            Spacer(minLength: 0)
            Image(systemName: "mic.fill").font(.system(size: 9))
        }
        .foregroundStyle(palette.dark ? .white.opacity(0.7) : .black.opacity(0.54))
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(palette.dark ? Color.white.opacity(0.10) : Color(hex: 0xEEEEEE))
        .clipShape(Capsule())
    }

    // MARK: Mood chips — the rail runs off the edge, like the real one

    private var moodChips: some View {
        // A scroll view is the one container that reports the *proposed* width
        // instead of its content's: this rail is wider than the mock, and a
        // plain HStack pushed the whole mock out of the frame.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(["Energize", "Relax", "Feel good", "Workout", "Party"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 5))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .padding(.horizontal, 7)
                        .frame(height: 10)
                        .background(palette.surfaceHigh)
                        .clipShape(Capsule())
                        .fixedSize()
                }
            }
        }
        .scrollDisabled(true)
        .frame(height: 10)
    }

    // MARK: Quick picks

    private var quickPicksHeader: some View {
        HStack {
            Text("Quick picks")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.accent)
            Spacer()
            Text("Play all")
                .font(.system(size: 4.5, weight: .medium))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 8)
                .frame(height: 10)
                .overlay(Capsule().strokeBorder(palette.accent.opacity(0.7), lineWidth: 0.6))
        }
    }

    private var songRows: some View {
        // Art size follows the grid-size setting, as the Kotlin preview does.
        let artSize: CGFloat = look.gridItemSize == .big ? 28 : 23
        let artTints: [Color] = [palette.accent.opacity(0.35),
                                 palette.accent.opacity(0.2),
                                 palette.surfaceHigh]
        return VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(artTints[i % artTints.count])
                        .frame(width: artSize, height: artSize)
                    Spacer().frame(width: 8)
                    VStack(alignment: .leading, spacing: 3) {
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(palette.onSurface.opacity(0.85))
                                .frame(width: g.size.width * 0.68, height: 5)
                        }
                        .frame(height: 5)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(palette.onSurfaceVariant.opacity(0.6))
                                .frame(width: g.size.width * 0.44, height: 4)
                        }
                        .frame(height: 4)
                    }
                    Spacer().frame(width: 6)
                    VStack(spacing: 1.5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(palette.onSurfaceVariant.opacity(0.6))
                                .frame(width: 2.5, height: 2.5)
                        }
                    }
                }
            }
        }
    }

    // MARK: Mini player — real art + title, in the chosen design and background

    private var miniPlayer: some View {
        let design = look.miniPlayerDesign
        let bg = look.miniPlayerBackground
        let isFloating = design == .floating
        let isFlat = design == .flat

        let onMini: Color = {
            switch bg {
            case .gradient: return palette.onAccent
            case .pureBlack: return .white
            default: return palette.onSurface
            }
        }()

        return HStack(spacing: 0) {
            RemoteImage(url: player.current?.artURL(size: 120), size: 18) {
                onMini.opacity(0.85)
            }
            .frame(width: 18, height: 18)
            .clipShape(isFlat || isFloating
                       ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                       : AnyShape(Circle()))

            Spacer().frame(width: 5)
            VStack(alignment: .leading, spacing: 0.5) {
                Text(player.current?.title ?? "Song title")
                    .font(.system(size: 6, weight: .bold)).lineLimit(1)
                Text(player.current?.artist ?? "Artist")
                    .font(.system(size: 4.5)).opacity(0.7).lineLimit(1)
            }
            .foregroundStyle(onMini)
            Spacer(minLength: 5)

            switch design {
            case .rounded:
                HStack(spacing: 1.5) {
                    Image(systemName: "backward.end.fill").font(.system(size: 6))
                        .foregroundStyle(onMini)
                    Circle().fill(onMini)
                        .frame(width: 11, height: 11)
                        .overlay(Image(systemName: "play.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(bg == .gradient ? palette.accent : palette.surface))
                    Image(systemName: "forward.end.fill").font(.system(size: 6))
                        .foregroundStyle(onMini)
                }
            case .flat:
                Image(systemName: "heart").font(.system(size: 7)).foregroundStyle(onMini)
            default:
                HStack(spacing: 4) {
                    Image(systemName: "text.badge.plus").font(.system(size: 7))
                    Image(systemName: "heart").font(.system(size: 7))
                }
                .foregroundStyle(onMini.opacity(0.9))
            }
        }
        .padding(.horizontal, 5)
        // 64pt on a 393pt phone scales to ~25pt on this ~149pt-wide mock.
        .frame(height: 25)
        .frame(maxWidth: .infinity)
        .background(miniBackground)
        .clipShape(RoundedRectangle(cornerRadius: isFlat ? 5 : (isFloating ? 9 : 12.5),
                                    style: .continuous))
        .shadow(color: isFloating ? .black.opacity(0.3) : .clear, radius: 4, y: 2)
        .padding(.horizontal, isFloating ? 8 : 0)
    }

    @ViewBuilder private var miniBackground: some View {
        switch look.miniPlayerBackground {
        case .gradient:
            LinearGradient(colors: [palette.accent, palette.accent.opacity(0.72)],
                           startPoint: .leading, endPoint: .trailing)
        case .pureBlack: Color.black
        case .blur: palette.surfaceHigh
        default: palette.surfaceHigh
        }
    }

    // MARK: Nav bar — real icons, the default-open tab highlighted per style

    private var navBar: some View {
        let icons: [(DefaultTab, String)] = [
            (.home, "house.fill"), (.explore, "magnifyingglass"),
            (.yours, "square.grid.2x2"), (.library, "books.vertical"),
        ]
        return HStack {
            ForEach(icons, id: \.1) { tab, icon in
                let active = tab == look.defaultTab
                let tint: Color = active ? palette.accent : palette.onSurfaceVariant.opacity(0.55)
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: look.slimNavBar ? 10 : 12))
                        .foregroundStyle(active && look.navBarStyle == .gradient ? palette.onAccent : tint)
                        .padding(.horizontal, active && look.navBarStyle != .underline ? 5 : 0)
                        .padding(.vertical, active && look.navBarStyle != .underline ? 2 : 0)
                        .background(navHighlight(active))
                    if !look.slimNavBar, look.navBarStyle != .gradient {
                        Capsule().fill(tint.opacity(active ? 1 : 0.5))
                            .frame(width: 12, height: 2.5)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func navHighlight(_ active: Bool) -> some View {
        if active {
            switch look.navBarStyle {
            case .pill: Capsule().fill(palette.accent.opacity(0.22))
            case .gradient:
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: [palette.accent,
                                                  palette.accent.mixed(with: .black, 0.3)],
                                         startPoint: .leading, endPoint: .trailing))
            case .outlined:
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(palette.accent.opacity(0.14))
            case .underline: Color.clear
            }
        } else {
            Color.clear
        }
    }
}

/// Faithful port of `LyricsSampleInterior`: Language pill, three stanzas spread
/// down the page (dim · bright · dim) aligned per the position setting, then the
/// song bar (real art · title/artist · fullscreen/theme/more) and the progress
/// bar with times, over the tinted gradient.
struct LookFeelLyricsPreview: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    let position: LyricsPosition

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 24)

            HStack(spacing: 3) {
                Image(systemName: "character.bubble").font(.system(size: 6))
                Text("Language").font(.system(size: 5.5))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(.white.opacity(0.16))
            .clipShape(Capsule())

            // Stanzas fill the page height, spread evenly like the real screen.
            VStack(spacing: 0) {
                Spacer()
                stanza("Baatein teri,\nraatein-saugaate\nin teri", dim: true, size: 10)
                Spacer()
                stanza("Kyun tera sab\nyeh ho gaya?\nHua kya?", dim: false, size: 13)
                Spacer()
                stanza("Main kahin bhi\njaata hoon, tum\nse hi mil jaata hoon", dim: true, size: 10)
                Spacer()
            }
            .frame(maxHeight: .infinity)

            // Song bar: real art · title/artist · fullscreen / theme / more.
            HStack(spacing: 0) {
                RemoteImage(url: player.current?.artURL(size: 120), size: 20) {
                    palette.accent
                }
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Spacer().frame(width: 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.current?.title ?? "Song title")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(player.current?.artist ?? "Artist")
                        .font(.system(size: 5.5))
                        .foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 4)

                ForEach(["arrow.up.left.and.arrow.down.right", "paintpalette", "ellipsis"],
                        id: \.self) { icon in
                    Circle().fill(.white)
                        .frame(width: 13, height: 13)
                        .overlay(Image(systemName: icon)
                            .font(.system(size: 6))
                            .foregroundStyle(.black))
                        .padding(.leading, 3)
                }
            }

            Spacer().frame(height: 7)
            // Progress + times.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(palette.accent).frame(width: g.size.width * 0.48)
                }
            }
            .frame(height: 3)
            Spacer().frame(height: 3)
            HStack {
                Text("2:33")
                Spacer()
                Text("5:21")
            }
            .font(.system(size: 5))
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [palette.accent.mixed(with: .black, 0.62), palette.scaffold],
                           startPoint: .top, endPoint: .bottom),
        )
    }

    private func stanza(_ text: String, dim: Bool, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white.opacity(dim ? 0.30 : 1))
            .multilineTextAlignment(position.textAlignment)
            .frame(maxWidth: .infinity, alignment: position.frameAlignment)
    }
}
