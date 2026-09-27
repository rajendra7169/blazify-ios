import SwiftUI

/// The pinned tiles at the top of Home.
///
/// Two rows that scroll sideways: a square of art per pin with its name across
/// the bottom, the way the Android home does it. A song plays where it is; a
/// playlist or an artist opens. Long-press unpins, which is the only way back
/// out of a tile that has nothing else to press.
struct SpeedDialGrid: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var dial = SpeedDial.shared
    @ObservedObject var player: Player
    /// Where a playlist or an artist goes.
    let onOpen: (HomeItem) -> Void

    private let side: CGFloat = 116

    var body: some View {
        if !dial.pins.isEmpty {
            BlazeSectionHeader(title: "Speed dial")
            ScrollView(.horizontal, showsIndicators: false) {
                // Two rows, filled column by column, so a short dial is one row
                // of tiles rather than a row of gaps.
                LazyHGrid(rows: rows, spacing: 12) {
                    ForEach(dial.pins) { pin in
                        tile(pin)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private var rows: [GridItem] {
        let count = dial.pins.count > 3 ? 2 : 1
        return Array(repeating: GridItem(.fixed(side), spacing: 12), count: count)
    }

    private func tile(_ pin: SpeedDial.Pin) -> some View {
        Button {
            switch pin.kind {
            case .song:
                // The rest of the dial goes behind it: a tile that plays one song
                // and stops is the same dead end a single card always was.
                let queue = dial.songs
                let start = queue.firstIndex { $0.videoId == pin.key } ?? 0
                player.play(queue.isEmpty ? [pin.track] : queue, startAt: start)
                player.showFullPlayer = true
            case .playlist, .artist:
                onOpen(pin.item)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: URL(string: pin.thumbnail), size: side) {
                    palette.onSurface.opacity(0.06)
                        .overlay(Image(systemName: pin.kind == .artist ? "person.fill" : "music.note")
                            .foregroundStyle(palette.onSurfaceVariant))
                }
                .frame(width: side, height: side)
                .clipped()

                // Dark at the top for the pin, dark at the bottom for the name.
                LinearGradient(colors: [.black.opacity(0.4), .clear,
                                        .black.opacity(0.6), .black.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)

                HStack(spacing: 4) {
                    Text(pin.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if pin.kind != .song {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(8)

                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(width: side, height: side, alignment: .topTrailing)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(player.current?.videoId == pin.key
                            ? palette.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { dial.unpin(pin.key) } label: {
                Label("Unpin", systemImage: "pin.slash")
            }
        }
    }
}
