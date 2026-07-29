import SwiftUI

/// Shared chrome for the settings sheets. Each sheet is its own presentation, so
/// the root's mini player is covered by every one of them — this puts it back,
/// on every page, and routes a tap to the root's full player.
struct SettingsMiniPlayer: ViewModifier {
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.current != nil {
                MiniPlayerView(player: player) {
                    // The full player belongs to the root, so this sheet has to
                    // step aside or it would open behind us.
                    dismiss()
                    player.showFullPlayer = true
                }
                .padding(.bottom, 6)
            }
        }
    }
}

extension View {
    /// Adds the mini player to a settings page.
    func settingsMiniPlayer(_ player: Player) -> some View {
        modifier(SettingsMiniPlayer(player: player))
    }
}
