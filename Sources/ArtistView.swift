import SwiftUI

/// Artist channel page: square photo header with the name and subscriber count
/// over it, a shuffle CTA, then the artist's shelves — song lists inline, and
/// albums / singles / similar artists as horizontal card rows.
struct ArtistView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var auth = Auth.shared
    /// Flipped immediately on tap so the button responds, then reverted if the
    /// account refuses.
    @State private var following: Bool?
    @State private var followBusy = false
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
                        Image(systemName: "person.slash").font(.blaze(36))
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
        .task { await load() }
    }

    private func header(_ page: ArtistPage) -> some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { g in
                RemoteImage(url: page.thumbnailURL, size: 420) { ArtPlaceholder() }
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
                    .font(.blaze(32, .bold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    if !page.subscribers.isEmpty, ContentPrefs.shared.showSubscriberCount {
                        Text(page.subscribers)
                            .font(.blaze(13))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                    if auth.isLoggedIn, page.channelId != nil {
                        followButton
                    }
                }
                if let songs = firstSongs, !songs.isEmpty {
                    Button {
                        player.play(songs.shuffled(), startAt: 0)
                        player.showFullPlayer = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "shuffle")
                            Text("Shuffle").font(.blaze(15, .semibold))
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
                .font(.blaze(20, .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)
        }

        if !section.songs.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(Array(section.songs.enumerated()), id: \.element.id) { pair in
                    SongRow(track: pair.element, player: player) {
                        player.play(section.songs, startAt: pair.offset)
                        player.showFullPlayer = true
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 6)
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

    /// Follow / following, with the state flipped optimistically so the tap
    /// feels instant and reverted if YouTube refuses.
    @ViewBuilder private var followButton: some View {
        let isFollowing = following ?? (page?.following ?? false)
        Button {
            toggleFollow(currently: isFollowing)
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.blaze(13, .semibold))
                .foregroundStyle(isFollowing ? palette.onSurface : palette.onAccent)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(isFollowing ? AnyShapeStyle(palette.surfaceHigh)
                                        : AnyShapeStyle(palette.accent))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(followBusy)
        .opacity(followBusy ? 0.6 : 1)
    }

    private func toggleFollow(currently: Bool) {
        guard let channelId = page?.channelId, !followBusy else { return }
        let wanted = !currently
        following = wanted
        followBusy = true
        Task {
            let ok = await YouTube.setFollowing(wanted, channelId: channelId)
            await MainActor.run {
                followBusy = false
                if !ok { following = currently }
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
