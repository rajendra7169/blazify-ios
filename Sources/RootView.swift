import SwiftUI

/// App root: search over a dark scaffold, a mini-player pinned above the content,
/// and the full player as a sheet. (Home/Library tabs come in the next chunk.)
struct RootView: View {
    @StateObject private var player = Player()

    var body: some View {
        NavigationStack {
            SearchView(player: player)
                .safeAreaInset(edge: .bottom) {
                    if player.hasTrack {
                        MiniPlayerView(player: player)
                            .padding(.bottom, 6)
                    }
                }
        }
        .preferredColorScheme(.dark)
        .tint(Blaze.amber)
        .sheet(isPresented: $player.showFullPlayer) {
            PlayerView(player: player)
        }
    }
}
