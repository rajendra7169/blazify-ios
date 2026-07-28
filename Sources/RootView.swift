import SwiftUI
import UIKit

/// App shell: the four-tab home experience from BlazePlayer — Home feed, Explore
/// (search), Favorites, Profile — with a custom amber bottom nav, the mini-player
/// pinned above it, and the full player as a sheet.
struct RootView: View {
    @ObservedObject private var theme = AppTheme.shared
    @StateObject private var player = Player()
    @State private var tab: BlazeTab = .home
    @Environment(\.colorScheme) private var scheme

    /// Home-indicator height. Measured once on appear — reading UIKit's window
    /// on every body pass is the kind of thing that upsets SwiftUI's layout.
    @State private var safeBottom: CGFloat = 34

    /// Mini-player (64 + 8 gap) plus the 70pt bar plus the home indicator.
    /// Pages add this as bottom padding themselves — see `playerBottomPadding()`.
    private var bottomInset: CGFloat { (player.hasTrack ? 72 : 0) + 70 + safeBottom }

    @State private var showRecognition = false

    private var palette: Palette { Palette(dark: theme.isDark(scheme)) }

    /// Floating action above the mini-player: shuffle everywhere, but song
    /// recognition on Explore — matching where each belongs on Android.
    private var actionButton: some View {
        HStack {
            Spacer()
            Button {
                if tab == .explore { showRecognition = true } else { shuffleAll() }
            } label: {
                Image(systemName: tab == .explore ? "waveform" : "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 48, height: 48)
                    .background(palette.accent)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    /// Start a random song from everything you've liked or played.
    private func shuffleAll() {
        var pool = player.favoriteTracks + PlayHistory.recent + Downloads.shared.tracks
        var seen = Set<String>()
        pool = pool.filter { !$0.videoId.isEmpty && seen.insert($0.videoId).inserted }
        guard !pool.isEmpty else { return }
        player.isShuffled = true
        player.play(pool.shuffled(), startAt: 0)
        player.showFullPlayer = true
    }

    var body: some View {
        // The scaffold is a *background*, not a sibling: a full-bleed child would
        // make the stack itself full-bleed, and `safeAreaInset` below would then
        // stop reserving room — which is what let content slide under the bar.
        Group {
            switch tab {
            case .home:
                HomeView(player: player, tab: $tab)
            case .explore:
                NavigationStack { SearchView(player: player) }
            case .yours:
                YoursView(player: player)
            case .library:
                LibraryView(player: player)
            }
        }
        .background(palette.scaffold.ignoresSafeArea())
        // `safeAreaInset` — NOT an overlay. An overlay bar has to ignore the
        // safe area to sit under the home indicator, and that pushes its frame
        // off-screen: the buttons stop receiving taps and the mini-player gets
        // shoved out of view. This places the bar correctly and handles the home
        // indicator itself; pages still clear it via `playerBottomPadding()`,
        // because the inset doesn't reach inside each tab's NavigationStack.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                actionButton
                if player.hasTrack {
                    MiniPlayerView(player: player)
                        .padding(.bottom, 8)   // don't sit flush on the tab bar
                }
                BlazeTabBar(selection: $tab, palette: palette)
            }
        }
        .fullScreenCover(isPresented: $showRecognition) {
            RecognitionView(player: player)
                .environment(\.palette, palette)
        }
        .onAppear {
            safeBottom = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first?.safeAreaInsets.bottom ?? 34
        }
        .environment(\.palette, palette)
        .environment(\.playerBottomInset, bottomInset)
        .preferredColorScheme(theme.preferredColorScheme)
        .tint(palette.accent)
        .fullScreenCover(isPresented: $player.showFullPlayer) {
            PlayerView(player: player)
                .environment(\.palette, palette)
        }
    }
}

enum BlazeTab: CaseIterable {
    case home, explore, yours, library

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .explore: "safari.fill"
        case .yours: "sparkles"
        case .library: "books.vertical.fill"
        }
    }
    var label: String {
        switch self {
        case .home: "Home"
        case .explore: "Explore"
        case .yours: "Yours"
        case .library: "Library"
        }
    }
}

/// Flutter's custom 70pt bottom bar. The active tint follows the album-art
/// accent, so the bar recolours with the rest of the app.
struct BlazeTabBar: View {
    @Binding var selection: BlazeTab
    let palette: Palette

    var body: some View {
        HStack {
            ForEach(BlazeTab.allCases, id: \.self) { t in
                let active = t == selection
                Button {
                    selection = t
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon)
                            .font(.system(size: 24))
                        Text(t.label)
                            .font(.system(size: 11, weight: active ? .semibold : .regular))
                    }
                    .foregroundStyle(active ? palette.accent : palette.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    // Without this the button only accepts taps that land on a
                    // glyph, not anywhere in its column.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // 70pt exactly — `safeAreaInset` already leaves room for the home
        // indicator, so padding for it again is what made the bar too tall.
        .frame(height: 70)
        .background(palette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.separator).frame(height: 0.5)
        }
    }
}
