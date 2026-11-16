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
    /// An album or single opened from this page.
    @State private var openAlbum: HomeItem?
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
                        if let release = latestRelease(in: page) {
                            latestReleaseCard(release)
                        }
                        let yours = yourSongs(by: page)
                        if !yours.isEmpty {
                            yourSongsShelf(yours, artist: page.name)
                        }
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
            .navigationDestination(item: $openAlbum) { PlaylistView(item: $0, player: player) }
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
                        player.openFullPlayer()
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

    // MARK: Latest release and you

    /// The year in a card's line ("Album • 2024", "Single • 2025"), if it says one.
    private static func year(of item: HomeItem) -> Int? {
        guard let range = item.subtitle.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) else { return nil }
        return Int(item.subtitle[range])
    }

    /// Their newest single or album: YouTube lists newest first, so the first of the latest year.
    private func latestRelease(in page: ArtistPage) -> (item: HomeItem, year: Int)? {
        var best: (item: HomeItem, year: Int)?
        for card in page.sections.flatMap(\.cards) where card.browseId != nil && !card.isCircular {
            guard let year = Self.year(of: card) else { continue }
            if best == nil || year > best!.year { best = (card, year) }
        }
        return best
    }

    private func latestReleaseCard(_ release: (item: HomeItem, year: Int)) -> some View {
        Button { openAlbum = release.item } label: {
            HStack(spacing: 12) {
                RemoteImage(url: release.item.thumbnailURL, size: 120) { ArtPlaceholder() }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("LATEST RELEASE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(palette.accent)
                    Text(release.item.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(1)
                    Text(String(release.year))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            .padding(10)
            .background(palette.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    /// Your own songs by this artist, from this phone so it shows offline too: the ones you have
    /// listened to most, then liked ones, then downloaded ones; five at most.
    private func yourSongs(by page: ArtistPage) -> [Track] {
        let name = page.name.lowercased()
        func byThem(_ track: Track) -> Bool {
            if let id = track.artistId, id == browseId || id == page.channelId { return true }
            guard !name.isEmpty else { return false }
            return track.artist.lowercased()
                .components(separatedBy: CharacterSet(charactersIn: ",&•"))
                .contains { $0.trimmingCharacters(in: .whitespaces) == name }
        }
        var seen = Set<String>()
        var out: [Track] = []
        let played = PlayHistory.mostPlayed(.all, limit: 500).filter(byThem)
        for track in played + player.favoriteTracks.filter(byThem) + Downloads.shared.tracks.filter(byThem)
            where !track.videoId.isEmpty && seen.insert(track.videoId).inserted {
            out.append(track)
            if out.count == 5 { break }
        }
        return out
    }

    private func yourSongsShelf(_ songs: [Track], artist: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("You and \(artist)")
                .font(.blaze(20, .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { pair in
                    SongRow(track: pair.element, player: player) {
                        player.play(songs, startAt: pair.offset)
                        player.openFullPlayer()
                    }
                }
            }
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
                        player.openFullPlayer()
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
                                player.openFullPlayer()
                            } else if card.browseId != nil, !card.isCircular {
                                // Albums and singles open, as everywhere else in the app.
                                openAlbum = card
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
