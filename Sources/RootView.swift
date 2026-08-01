import SwiftUI
import UIKit

/// App shell: the four-tab home experience from BlazePlayer — Home feed, Explore
/// (search), Favorites, Profile — with a custom amber bottom nav, the mini-player
/// pinned above it, and the full player as a sheet.
struct RootView: View {
    @ObservedObject private var theme = AppTheme.shared
    @ObservedObject private var look = LookFeel.shared
    @StateObject private var player = Player()
    @State private var tab: BlazeTab = LookFeel.shared.defaultTab.tab
    @Environment(\.colorScheme) private var scheme

    /// Home-indicator height. Measured once on appear — reading UIKit's window
    /// on every body pass is the kind of thing that upsets SwiftUI's layout.
    @State private var safeBottom: CGFloat = 34

    /// Mini-player (64 + 8 gap) plus the 70pt bar plus the home indicator.
    /// Pages add this as bottom padding themselves — see `playerBottomPadding()`.
    private var bottomInset: CGFloat {
        (player.hasTrack ? 72 : 0) + (look.slimNavBar ? 54 : 70) + safeBottom
    }

    @State private var showRecognition = false
    /// Tabs built so far — we don't pay for a tab until it's opened, but once
    /// it's open it stays alive so its scroll position and data survive.
    @State private var visited: Set<BlazeTab> = [LookFeel.shared.defaultTab.tab]

    private var palette: Palette { Palette(dark: theme.isDark(scheme)) }

    @ViewBuilder
    private func tabContent(_ t: BlazeTab) -> some View {
        switch t {
        case .home: HomeView(player: player, tab: $tab)
        case .explore: NavigationStack { SearchView(player: player) }
        case .yours: YoursView(player: player)
        case .library: LibraryView(player: player)
        }
    }

    /// Floating action above the mini-player: shuffle everywhere, but song
 /// recognition on Explore — matching where each belongs.
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
    /// Act on whatever Siri or a Shortcut asked for. Intents can't touch the
    /// player directly — it's a `@StateObject` owned by this view — so they
    /// leave a request and we perform it here.
    private func performPendingRequest() {
        guard let request = BlazifyRequest.take() else { return }
        switch request {
        case .resume:
            if player.hasTrack, !player.isPlaying { player.toggle() }
            player.showFullPlayer = true
        case .favourites:
            let songs = player.favoriteTracks.shuffled()
            guard !songs.isEmpty else {
                // Doing nothing here is indistinguishable from "it just carried
                // on playing", which is what made this look broken.
                tab = .library
                return
            }
            player.isShuffled = true
            player.play(songs, startAt: 0)
            player.showFullPlayer = true
        case .downloads:
            let songs = Downloads.shared.tracks.shuffled()
            guard !songs.isEmpty else {
                tab = .library
                return
            }
            player.isShuffled = true
            player.play(songs, startAt: 0)
            player.showFullPlayer = true
        case .recognise:
            showRecognition = true
        case .play(let videoId):
            // Siri already resolved the song, so this is a direct play. The
            // related feed just supplies the title and artwork, and a queue to
            // carry on with once it ends.
            Task { @MainActor in
                let related = await YouTube.related(videoId: videoId)
                    .flatMap(\.items)
                    .filter { $0.browseId == nil }
                    .map(\.asTrack)
                let named = related.first { $0.videoId == videoId }
                let track = named ?? Track(videoId: videoId, title: "Song",
                                           artist: "", thumbnail: "", duration: 0)
                var queue = [track]
                queue += related.filter { $0.videoId != videoId }
                player.play(queue, startAt: 0)
                player.showFullPlayer = true
            }
        }
    }

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
        // Every visited tab stays in the hierarchy, just hidden. A `switch` here
        // tears the old tab down, so Home threw away its feed and reloaded from
        // scratch every time you came back from Yours.
        ZStack {
            ForEach(BlazeTab.allCases, id: \.self) { t in
                if visited.contains(t) {
                    tabContent(t)
                        .opacity(tab == t ? 1 : 0)
                        .allowsHitTesting(tab == t)
                        .zIndex(tab == t ? 1 : 0)
                }
            }
        }
        .onChange(of: tab) { visited.insert(tab) }
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
                BlazeTabBar(selection: $tab, palette: palette, look: look)
            }
            // Stay put when the keyboard opens: without this the whole bar
            // (and the mini-player) rides up and sits on top of the keyboard.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .fullScreenCover(isPresented: $showRecognition) {
            RecognitionView(player: player)
                .environment(\.palette, palette)
        }
        // Siri and Shortcuts leave a request rather than reaching into the
        // player directly; perform it once the app is up.
        .onAppear {
            performPendingRequest()
            PlayHistory.pruneOld()
            safeBottom = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first?.safeAreaInsets.bottom ?? 34
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            performPendingRequest()
        }
        // Home Screen widget tiles arrive as blazify:// URLs.
        .onOpenURL { url in
            guard let request = BlazifyLink.request(for: url) else { return }
            request.store()
            performPendingRequest()
        }
        .environment(\.palette, palette)
        .environment(\.playerBottomInset, bottomInset)
        .preferredColorScheme(theme.preferredColorScheme)
        .tint(palette.accent)
        .fullScreenCover(isPresented: $player.showFullPlayer) {
            PlayerView(player: player)
                .environment(\.palette, palette)
                // Clear, so dragging the player down reveals the app behind it
                // rather than a white sheet backdrop.
                .presentationBackground(.clear)
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

/// The bottom bar, per style:
/// PILL is Material's indicator — a fixed capsule behind the ICON only, label
/// outside it; GRADIENT and OUTLINED wrap icon+label in a rounded box;
/// UNDERLINE is a plain icon with a bar underneath. Slim hides the labels.
struct BlazeTabBar: View {
    @Binding var selection: BlazeTab
    let palette: Palette
    @ObservedObject var look: LookFeel

    var body: some View {
        HStack {
            ForEach(BlazeTab.allCases, id: \.self) { t in
                let active = t == selection
                Button {
                    selection = t
                } label: {
                    item(t, active: active)
                        .frame(maxWidth: .infinity)
                        // Without this the button only accepts taps that land on
                        // a glyph, not anywhere in its column.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: look.slimNavBar ? 54 : 70)
        .background(palette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.separator).frame(height: 0.5)
        }
    }

    private var idle: Color { palette.onSurfaceVariant }

    @ViewBuilder private func item(_ t: BlazeTab, active: Bool) -> some View {
        switch look.navBarStyle {
        case .pill:
            // Material's indicator: a fixed-size capsule behind the icon only.
            VStack(spacing: 3) {
                Image(systemName: t.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(active ? palette.accent : idle)
                    .frame(width: 56, height: 30)
                    .background(active ? AnyShapeStyle(palette.accent.opacity(0.22))
                                       : AnyShapeStyle(Color.clear))
                    .clipShape(Capsule())
                if !look.slimNavBar {
                    Text(t.label)
                        .font(.system(size: 11, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? palette.accent : idle)
                }
            }

        case .gradient:
            // The highlight wraps icon AND label, gradient-filled with a border.
            VStack(spacing: 2) {
                Image(systemName: t.icon)
                    .font(.system(size: 20))
                if !look.slimNavBar {
                    Text(t.label).font(.system(size: 11))
                }
            }
            .foregroundStyle(active ? palette.onAccent : idle)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(
                            colors: [palette.accent.opacity(0.85),
                                     palette.accent.mixed(with: .black, 0.3).opacity(0.85)],
                            startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(palette.accent.opacity(0.55), lineWidth: 1))
                }
            }

        case .outlined:
            // Tinted box with an accent border around icon and label.
            VStack(spacing: 2) {
                Image(systemName: t.icon)
                    .font(.system(size: 20))
                if !look.slimNavBar {
                    Text(t.label).font(.system(size: 11))
                }
            }
            .foregroundStyle(active ? palette.accent : idle)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.accent.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(palette.accent.opacity(0.7), lineWidth: 1))
                }
            }

        case .underline:
            VStack(spacing: 4) {
                Image(systemName: t.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(active ? palette.accent : idle)
                if !look.slimNavBar {
                    Text(t.label)
                        .font(.system(size: 11))
                        .foregroundStyle(active ? palette.accent : idle)
                }
                Capsule().fill(active ? palette.accent : .clear)
                    .frame(width: 22, height: 2.5)
            }
        }
    }
}
