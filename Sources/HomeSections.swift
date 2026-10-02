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
            // A shelf of songs is played, not browsed: no arrow, just the words.
            HomeSectionHeader(
                title: section.title,
                onPlayAll: section.items.isEmpty ? nil : {
                    player.play(section.items.map(\.asTrack), startAt: 0)
                },
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 12) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { pair in
                        Button {
                            player.play(section.items.map(\.asTrack), startAt: pair.offset)
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
    /// A row of songs is a thing to play, so it says so in words.
    var onPlayAll: (() -> Void)?
    /// A row of playlists, albums or artists is a thing to look through, so it
    /// gets the arrow into all of it instead.
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
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Play all")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
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
///
/// The row on Home is the handful of cards that fit across it. YouTube keeps the
/// rest behind the shelf's own endpoint, so this asks for that and shows what
/// comes back — falling back to the cards already in hand when a shelf has no
/// page of its own.
struct HomeSectionScreen: View {
    @Environment(\.palette) private var palette
    let section: HomeSection
    @ObservedObject var player: Player
    /// Cards that open a page hand it back to the screen that pushed this one,
    /// so the whole feed keeps one way in and out.
    let onOpen: (HomeItem) -> Void

    @State private var items: [HomeItem] = []
    @State private var loading = true
    @State private var next: String?
    @State private var extending = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    /// The songs among them, in order — what Play and Shuffle work on.
    private var songs: [Track] {
        items.filter { $0.browseId == nil && !($0.videoId ?? "").isEmpty }.map(\.asTrack)
    }

    /// Whether this shelf is songs and nothing else.
    ///
    /// Decided by what came back rather than by the heading: a row called
    /// "Singles" holds songs and one called "Albums" does not, and the heading
    /// is no guide to which. Songs belong in a list, where a title can be read
    /// and an artist sits beneath it; everything else belongs in artwork.
    private var isSongList: Bool {
        !items.isEmpty && items.allSatisfy { $0.browseId == nil && !($0.videoId ?? "").isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !songs.isEmpty {
                    actions
                }
                if isSongList {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { at, item in
                            songRow(item, at: at)
                        }
                    }
                    .padding(.top, 4)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            BlazeMusicCard(title: item.title, subtitle: item.subtitle,
                                           thumbnail: item.thumbnail, isCircular: item.isCircular,
                                           fallbackIcon: item.isCircular ? "person.fill" : "music.note") {
                                open(item)
                            }
                        }
                    }
                    .padding(16)
                }

                if loading || extending {
                    ProgressView()
                        .tint(palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// One song, drawn as the playlist screens draw it.
    ///
    /// Reaching the last few rows asks for the next page, so a long shelf
    /// arrives as it is read rather than all at once or not at all.
    private func songRow(_ item: HomeItem, at index: Int) -> some View {
        HStack(spacing: 0) {
            Button {
                open(item)
            } label: {
                TrackRow(track: item.asTrack)
                    .padding(.leading, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            SongRowMenu(track: item.asTrack, player: player,
                        onAddToPlaylist: nil, onOpenArtist: nil)
                .padding(.trailing, 8)
        }
        .onAppear {
            if index >= items.count - 5 { Task { await extend() } }
        }
    }

    /// Play and Shuffle, as a playlist has them.
    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                player.play(songs, startAt: 0)
            } label: {
                label("play.fill", "Play")
                    .foregroundStyle(.black)
                    .background(palette.heroGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                player.isShuffled = true
                player.play(songs.shuffled(), startAt: 0)
            } label: {
                label("shuffle", "Shuffle")
                    .foregroundStyle(palette.onSurface)
                    .background(palette.onSurface.opacity(0.10))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func label(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold))
            Text(text).font(.blaze(15, .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func load() async {
        // What is already on screen shows at once; the full shelf replaces it.
        await MainActor.run { if items.isEmpty { items = section.items } }
        guard let browseId = section.browseId, !browseId.isEmpty else {
            await MainActor.run { loading = false }
            return
        }
        let page = await YouTube.shelfPage(browseId: browseId, params: section.params)
        await MainActor.run {
            if !page.items.isEmpty { items = page.items }
            next = page.next
            loading = false
        }
    }

    /// The next page, once, however many rows ask for it at the same moment.
    private func extend() async {
        guard let token = next, !extending, let browseId = section.browseId else { return }
        await MainActor.run { extending = true }
        let page = await YouTube.shelfPage(browseId: browseId, params: section.params,
                                           continuation: token)
        await MainActor.run {
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            next = page.next
            extending = false
        }
    }

    private func open(_ item: HomeItem) {
        guard item.browseId == nil else {
            onOpen(item)
            return
        }
        let playable = items.filter { $0.browseId == nil && !($0.videoId ?? "").isEmpty }
        guard let at = playable.firstIndex(where: { $0.videoId == item.videoId }) else { return }
        player.play(playable.map(\.asTrack), startAt: at)
    }
}
