import SwiftUI

/// App shell: the four-tab home experience from BlazePlayer — Home feed, Explore
/// (search), Favorites, Profile — with a custom amber bottom nav, the mini-player
/// pinned above it, and the full player as a sheet.
struct RootView: View {
    @ObservedObject private var theme = AppTheme.shared
    @StateObject private var player = Player()
    @State private var tab: BlazeTab = .home
    @Environment(\.colorScheme) private var scheme

    /// Home-indicator height, so the bar clears it and content clears the bar.
    private var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }

    /// Mini-player (64 + 8 gap) plus the 70pt bar plus the home indicator.
    /// Pages add this as bottom padding themselves — see `playerBottomPadding()`.
    private var bottomInset: CGFloat { (player.hasTrack ? 72 : 0) + 70 + safeBottom }

    private var palette: Palette { Palette(dark: theme.isDark(scheme)) }

    var body: some View {
        // The scaffold is a *background*, not a sibling: a full-bleed child would
        // make the stack itself full-bleed, and `safeAreaInset` below would then
        // stop reserving room — which is what let content slide under the bar.
        Group {
            switch tab {
            case .home:
                HomeView(player: player)
            case .explore:
                NavigationStack { SearchView(player: player) }
            case .yours:
                YoursView(player: player)
            case .library:
                LibraryView(player: player)
            }
        }
        .background(palette.scaffold.ignoresSafeArea())
        // An overlay, not a safeAreaInset: the inset never reduced the layout
        // region here, so content kept scrolling under the bar. Pages now clear
        // it explicitly with `playerBottomPadding()`, which is one mechanism
        // instead of two disagreeing ones.
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if player.hasTrack {
                    MiniPlayerView(player: player)
                        .padding(.bottom, 8)   // don't sit flush on the tab bar
                }
                BlazeTabBar(selection: $tab, palette: palette, safeBottom: safeBottom)
            }
            .ignoresSafeArea(edges: .bottom)
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
    /// Home-indicator height, absorbed into the bar so its fill runs to the edge.
    var safeBottom: CGFloat = 0

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
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 70)
        .padding(.bottom, safeBottom)
        .background(palette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.separator).frame(height: 0.5)
        }
    }
}
