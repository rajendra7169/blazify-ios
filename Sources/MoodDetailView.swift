import SwiftUI

/// A Mood/Genre page: what YouTube Music puts together for this account in
/// that mood, then the playlists inside the tile in a 2-column grid.
///
/// The grid alone was the complaint: it is YouTube's editorial selection for
/// the country, the same for everybody, and in a country that gets little of
/// its own it is mostly somebody else's language. The shelves above it are
/// the Home feed filtered by the mood's chip — "Your Relax mix", the songs you
/// play in that mood — which is the one place YouTube's own personalisation
/// reaches a mood. Genres have no chip, and get the grid alone.
struct MoodDetailView: View {
    @Environment(\.palette) private var palette
    let mood: MoodItem
    @ObservedObject var player: Player

    @State private var forYou: [HomeSection] = []
    @State private var playlists: [HomeItem] = []
    @State private var loading = true
    /// A card from one of the shelves, opened over this page. Its own type,
    /// not a bare HomeItem: the stack above already answers HomeItem by value
    /// for the grid, and two destinations for one type make a tap ambiguous.
    @State private var openCard: CardRoute?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if loading {
                SkeletonGrid()
            } else if playlists.isEmpty, forYou.isEmpty {
                Text("Nothing here")
                    .foregroundStyle(palette.onSurfaceVariant)
                    .padding(.top, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(forYou) { section in
                        if section.isSongs {
                            QuickPicksGrid(section: section, player: player)
                        } else {
                            HomeRail(section: section, onTap: { tap($0, within: $1) })
                        }
                    }

                    if !playlists.isEmpty {
                        if !forYou.isEmpty {
                            HomeSectionHeader(title: String(localized: "Playlists"))
                        }
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(playlists) { item in
                                // Resolves to the stack's HomeItem destination (PlaylistView).
                                NavigationLink(value: item) { PlaylistGridCard(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .playerBottomInsetArea()
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle(mood.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openCard) { PlaylistView(item: $0.item, player: player) }
        .task {
            // Both at once: the shelves are a Home request, the grid a browse,
            // and neither has to wait for the other.
            async let shelves = YouTube.moodShelves(for: mood.title)
            async let grid = YouTube.moodPlaylists(browseId: mood.browseId ?? "", params: mood.params)
            let (s, g) = await (shelves, grid)
            await MainActor.run {
                forYou = s
                playlists = g
                loading = false
            }
        }
    }

    /// As on Home: a playlist or album opens, a song plays with the rest of
    /// its row behind it.
    private func tap(_ item: HomeItem, within row: [HomeItem]) {
        guard item.browseId == nil else {
            openCard = CardRoute(item: item)
            return
        }
        guard let vid = item.videoId, !vid.isEmpty else { return }
        let songs = row.filter { $0.browseId == nil && !($0.videoId ?? "").isEmpty }
        if songs.isEmpty {
            player.playWithRadio(item.asTrack)
        } else {
            let start = songs.firstIndex { $0.videoId == vid } ?? 0
            player.play(songs.map(\.asTrack), startAt: start)
        }
    }
}
