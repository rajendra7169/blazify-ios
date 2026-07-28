import SwiftUI

/// Category chips under the greeting (All / Relax / Workout…). Tapping re-browses
/// the home feed filtered to that mood.
struct ChipsRow: View {
    @Environment(\.palette) private var palette
    let chips: [HomeChip]
    let selected: HomeChip?
    let onSelect: (HomeChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let isSelected = (selected?.title ?? chips.first?.title) == chip.title
                    Text(chip.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? palette.onAccent : palette.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isSelected ? AnyShapeStyle(palette.accent) : AnyShapeStyle(palette.onSurface.opacity(0.06)))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { onSelect(chip) }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }
}

/// Quick Picks: individual songs in a 4-row, horizontally-paged grid. Tap plays
/// the whole shelf from that song.
struct QuickPicksGrid: View {
    @Environment(\.palette) private var palette
    let section: HomeSection
    @ObservedObject var player: Player

    private let rows = Array(repeating: GridItem(.fixed(56), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 12) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { pair in
                        Button {
                            player.play(section.items.map(\.asTrack), startAt: pair.offset)
                            player.showFullPlayer = true
                        } label: {
                            cell(pair.element)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func cell(_ item: HomeItem) -> some View {
        HStack(spacing: 10) {
            RemoteImage(url: item.thumbnailURL) { palette.onSurface.opacity(0.06) }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.onSurface).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 250, alignment: .leading)
    }
}

/// Colored Mood & Genres tiles (2 rows, horizontal scroll).
struct MoodTiles: View {
    @Environment(\.palette) private var palette
    let moods: [MoodItem]
    let onTap: (MoodItem) -> Void

    private let rows = Array(repeating: GridItem(.fixed(52), spacing: 10), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Moods & genres")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 10) {
                    ForEach(moods) { mood in
                        Button { onTap(mood) } label: {
                            Text(mood.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.onSurface)
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                                .frame(width: 150, height: 52, alignment: .leading)
                                .background(Color(hex: mood.colorARGB & 0xFFFFFF))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// Square playlist/album tile for 2-column grids (library, mood detail).
struct PlaylistGridCard: View {
    @Environment(\.palette) private var palette
    let item: HomeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: item.thumbnailURL) {
                palette.onSurface.opacity(0.06)
                    .overlay(Image(systemName: "music.note.list")
                        .font(.system(size: 36))
                        .foregroundStyle(palette.onSurface.opacity(0.35)))
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.onSurface).lineLimit(1)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
            }
        }
    }
}
