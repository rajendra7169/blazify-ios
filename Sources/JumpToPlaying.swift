import SwiftUI

/// A pill that appears when the playing song has scrolled out of sight, and takes
/// you back to it.
///
/// Shown only when there is something to jump to and it is off screen — a button
/// that scrolls you to where you already are is noise.
struct JumpToPlayingButton: View {
    @Environment(\.palette) private var palette
    /// The row to jump to, or nil when this list has no playing song in it.
    let target: String?
    /// Whether that row is currently on screen.
    let isVisible: Bool
    let onJump: () -> Void

    var body: some View {
        if target != nil, !isVisible {
            Button(action: onJump) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Jump to playing")
                        .font(.blaze(14, .semibold))
                }
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(palette.surfaceHigh)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Tracks whether a given row is on screen, for lists that want the jump pill.
///
/// SwiftUI has no equivalent of asking a list which rows are visible, so each row
/// reports itself as it appears and disappears.
@MainActor
final class VisibleRows: ObservableObject {
    @Published private(set) var visible: Set<String> = []

    func appeared(_ id: String) { visible.insert(id) }
    func disappeared(_ id: String) { visible.remove(id) }
    func contains(_ id: String?) -> Bool {
        guard let id else { return false }
        return visible.contains(id)
    }
}

extension View {
    /// Reports this row's comings and goings, so the jump pill knows to show.
    func tracksVisibility(_ id: String, in rows: VisibleRows) -> some View {
        onAppear { rows.appeared(id) }
            .onDisappear { rows.disappeared(id) }
    }
}
