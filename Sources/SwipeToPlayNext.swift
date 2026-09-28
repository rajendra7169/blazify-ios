import SwiftUI

/// Swipe a song to the right and it comes up next.
///
/// The queue gets this from the system, because it is a `List`. Every other song
/// list here is drawn by hand, so it needs its own gesture — and the gesture is
/// worth having everywhere: choosing what comes next is what people do with a
/// list they are already looking at, and the alternative is the menu.
struct PlayNextSwipe: ViewModifier {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    let track: Track

    /// How far it has been pulled, while a finger is on it.
    @State private var offset: CGFloat = 0
    /// Briefly true after it has been queued, so the row can say so.
    @State private var queued = false

    /// Past this, letting go queues the song.
    private let commit: CGFloat = 78

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            if offset > 2 || queued {
                HStack(spacing: 8) {
                    Image(systemName: queued ? "checkmark" : "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 15, weight: .bold))
                    Text(queued ? "Playing next" : "Play next")
                        .font(.blaze(13, .semibold))
                }
                .foregroundStyle(offset >= commit || queued ? Blaze.amber : palette.onSurfaceVariant)
                .padding(.leading, 20)
            }

            content
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 22)
                        .onChanged { g in
                            // Sideways only, and only to the right: a list is
                            // scrolled far more often than a song is queued.
                            guard g.translation.width > 0,
                                  abs(g.translation.width) > abs(g.translation.height) * 1.5
                            else { return }
                            offset = min(g.translation.width, commit + 24)
                        }
                        .onEnded { _ in
                            let far = offset >= commit
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
                            guard far else { return }
                            player.playNext(track)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation { queued = true }
                            Task {
                                try? await Task.sleep(nanoseconds: 1_200_000_000)
                                withAnimation { queued = false }
                            }
                        },
                )
        }
    }
}

extension View {
    /// Swipe right on this row to put the song next in the queue.
    func swipeToPlayNext(_ track: Track, player: Player) -> some View {
        modifier(PlayNextSwipe(player: player, track: track))
    }
}
