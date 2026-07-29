import SwiftUI

/// Listening stats, ported from StatsScreen.kt: a period chip row (1 week →
/// all time) over the most-played songs and artists for that window.
struct StatsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player

    @State private var period: StatPeriod = .week1
    @State private var route: LibraryRoute?

    private var songs: [Track] { PlayHistory.mostPlayed(period, limit: 50) }
    private var artists: [(name: String, plays: Int)] { PlayHistory.topArtists(period, limit: 20) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                periodChips

                if songs.isEmpty {
                    Text("Nothing played in this period yet.")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }

                if !songs.isEmpty {
                    BlazeSectionHeader(title: "\(songs.count) songs") {
                        route = .tracks("Most played", songs)
                    }
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, track in
                        Button {
                            player.play(songs, startAt: index)
                            player.showFullPlayer = true
                        } label: {
                            rankedRow(index: index, track: track)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !artists.isEmpty {
                    BlazeSectionHeader(title: "Top artists")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(artists, id: \.name) { artist in
                                BlazeMusicCard(
                                    title: artist.name,
                                    subtitle: "\(artist.plays) play\(artist.plays == 1 ? "" : "s")",
                                    thumbnail: artistThumb(artist.name),
                                    isCircular: true, fallbackIcon: "person.fill",
                                ) {
                                    Task {
                                        if let id = await YouTube.resolveArtistId(name: artist.name) {
                                            await MainActor.run { route = .artist(id) }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

            }
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { LibraryRouteView(route: $0, player: player) }
    }

    /// Reuse a played song's art so an artist card isn't blank.
    private func artistThumb(_ name: String) -> String? {
        PlayHistory.tracks.first { $0.artist.localizedCaseInsensitiveContains(name) }?.thumbnail
    }

    private var periodChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StatPeriod.allCases) { option in
                    let active = option == period
                    Text(option.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? palette.onAccent : palette.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(active ? AnyShapeStyle(palette.accent)
                                           : AnyShapeStyle(palette.onSurface.opacity(0.06)))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { period = option }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    private func rankedRow(index: Int, track: Track) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(width: 24, alignment: .trailing)
            TrackRow(track: track)
            Text("\(PlayHistory.playCount(track.videoId, in: period))×")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
            SongRowMenu(track: track, player: player)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
