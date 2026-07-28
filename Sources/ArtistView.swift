import SwiftUI

/// Artist channel page: square photo header with the name and subscriber count
/// over it, a shuffle CTA, then the artist's shelves — song lists inline, and
/// albums / singles / similar artists as horizontal card rows.
struct ArtistView: View {
    @Environment(\.palette) private var palette
    let browseId: String
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    @State private var page: ArtistPage?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                if loading {
                    VStack(alignment: .leading, spacing: 0) {
                        SkeletonBox(height: 320, corner: 0)
                        SkeletonTrackList(rows: 4).padding(.top, 20)
                        SkeletonRail()
                    }
                } else if let page {
                    VStack(alignment: .leading, spacing: 0) {
                        header(page)
                        ForEach(page.sections) { section in
                            sectionView(section)
                        }
                    }
                    .playerBottomPadding()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "person.slash").font(.system(size: 36))
                            .foregroundStyle(palette.onSurfaceVariant)
                        Text("Couldn't load this artist")
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                    .padding(.top, 80)
                }
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(palette.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private func header(_ page: ArtistPage) -> some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { g in
                RemoteImage(url: page.thumbnailURL) { ArtPlaceholder() }
                    .frame(width: g.size.width, height: g.size.width)
                    .clipped()
                    .overlay(
                        LinearGradient(colors: [.clear, .black.opacity(0.85)],
                                       startPoint: .center, endPoint: .bottom),
                    )
            }
            .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 8) {
                Text(page.name)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(2)
                if !page.subscribers.isEmpty {
                    Text(page.subscribers)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                if let songs = firstSongs, !songs.isEmpty {
                    Button {
                        player.play(songs.shuffled(), startAt: 0)
                        player.showFullPlayer = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "shuffle")
                            Text("Shuffle").font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 11)
                        .background(palette.heroGradient)
                        .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
    }

    /// The first song shelf, used by the shuffle button.
    private var firstSongs: [Track]? {
        page?.sections.first(where: { !$0.songs.isEmpty })?.songs
    }

    @ViewBuilder private func sectionView(_ section: ArtistSection) -> some View {
        if !section.title.isEmpty {
            Text(section.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)
        }

        if !section.songs.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(Array(section.songs.enumerated()), id: \.element.id) { pair in
                    Button {
                        player.play(section.songs, startAt: pair.offset)
                        player.showFullPlayer = true
                    } label: {
                        TrackRow(track: pair.element)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(section.cards) { card in
                        MusicCard(item: card) {
                            if let vid = card.videoId, !vid.isEmpty {
                                player.play([card.asTrack], startAt: 0)
                                player.showFullPlayer = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func load() async {
        loading = true
        let p = await YouTube.artist(browseId: browseId)
        await MainActor.run {
            page = p
            loading = false
        }
    }
}
