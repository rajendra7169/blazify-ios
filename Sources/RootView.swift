import SwiftUI

/// App shell: the four-tab home experience from BlazePlayer — Home feed, Explore
/// (search), Favorites, Profile — with a custom amber bottom nav, the mini-player
/// pinned above it, and the full player as a sheet.
struct RootView: View {
    @StateObject private var player = Player()
    @State private var tab: BlazeTab = .home

    var body: some View {
        ZStack {
            Blaze.scaffold.ignoresSafeArea()

            switch tab {
            case .home:
                HomeView(player: player)
            case .explore:
                NavigationStack { SearchView(player: player) }
            case .favorites:
                SignInPrompt(icon: "heart.fill", message: "Sign in to see your favorites")
            case .profile:
                SignInPrompt(icon: "person.fill", message: "Sign in to Blazify")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if player.hasTrack {
                    MiniPlayerView(player: player)
                }
                BlazeTabBar(selection: $tab)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Blaze.amber)
        .sheet(isPresented: $player.showFullPlayer) {
            PlayerView(player: player)
        }
    }
}

enum BlazeTab: CaseIterable {
    case home, explore, favorites, profile

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .explore: "safari.fill"
        case .favorites: "heart.fill"
        case .profile: "person.fill"
        }
    }
    var label: String {
        switch self {
        case .home: "Home"
        case .explore: "Explore"
        case .favorites: "Favorites"
        case .profile: "Profile"
        }
    }
}

/// Flutter's custom 70pt bottom bar: amber active tint, #1E1E1E surface, top hairline.
struct BlazeTabBar: View {
    @Binding var selection: BlazeTab

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
                    .foregroundStyle(active ? Blaze.amber : Color.white.opacity(0.54))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 70)
        .background(Blaze.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
        }
    }
}

/// Placeholder for the tabs that need sign-in (Favorites / Profile), coming next chunk.
struct SignInPrompt: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Blaze.amber)
            Text(message)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Blaze.scaffold.ignoresSafeArea())
    }
}
