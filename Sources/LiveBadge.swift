import SwiftUI

/// The mark a broadcast gets where a song would show its time.
///
/// A station is only ever wherever it is right now: there is no length to read
/// and no position within it, so a time and a slider would both be fiction. This
/// says what it is instead.
struct LiveBadge: View {
    /// Red wherever it is drawn, because that is what a live mark means
    /// everywhere else; it never takes the album's colour.
    static let red = Color(hex: 0xE53935)

    var color: Color = LiveBadge.red

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.18))
        .clipShape(Capsule())
    }
}
