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

    /// Where "see all" goes. Nil leaves the row without one.
    var onSeeAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSectionHeader(
                title: section.title,
                onPlayAll: section.items.isEmpty ? nil : {
                    player.play(section.items.map(\.asTrack), startAt: 0)
                    player.showFullPlayer = true
                },
                onSeeAll: onSeeAll,
            )

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
            RemoteImage(url: item.thumbnailURL, size: 48) { palette.onSurface.opacity(0.06) }
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

/// A home row's heading, with the two things Android puts beside it: a button
/// that plays the whole row, and a way into all of it.
///
/// Without them a row was only ever the handful of cards that fit on screen —
/// the rest of it had nowhere to go.
struct HomeSectionHeader: View {
    @Environment(\.palette) private var palette
    let title: String
    var onPlayAll: (() -> Void)?
    var onSeeAll: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let onPlayAll {
                Button(action: onPlayAll) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play all")
            }
            if let onSeeAll {
                Button(action: onSeeAll) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

/// Everything in one home row, on a page of its own.
struct HomeSectionScreen: View {
    @Environment(\.palette) private var palette
    let section: HomeSection
    @ObservedObject var player: Player
    /// Cards that open a page hand it back to the screen that pushed this one,
    /// so the whole feed keeps one way in and out.
    let onOpen: (HomeItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(section.items) { item in
                    BlazeMusicCard(title: item.title, subtitle: item.subtitle,
                                   thumbnail: item.thumbnail, isCircular: item.isCircular,
                                   fallbackIcon: item.isCircular ? "person.fill" : "music.note") {
                        open(item)
                    }
                }
            }
            .padding(16)
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func open(_ item: HomeItem) {
        guard item.browseId == nil else {
            onOpen(item)
            return
        }
        let songs = section.items.filter { $0.browseId == nil && !($0.videoId ?? "").isEmpty }
        guard !songs.isEmpty, let at = songs.firstIndex(where: { $0.videoId == item.videoId })
        else { return }
        player.play(songs.map(\.asTrack), startAt: at)
        player.showFullPlayer = true
    }
}
