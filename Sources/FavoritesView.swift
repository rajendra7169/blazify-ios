import SwiftUI

/// Favorites tab: the signed-in user's saved & created playlists, tap to open.
struct FavoritesView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var auth = Auth.shared
    @ObservedObject var player: Player

    @State private var playlists: [HomeItem] = []
    @State private var liked: [Track] = []
    @State private var loading = false
    @State private var showLogin = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// Locally favourited tracks merged with the account's Liked songs.
    private var likedAll: [Track] {
        var seen = Set(player.favoriteTracks.map(\.videoId))
        var out = player.favoriteTracks
        for t in liked where !seen.contains(t.videoId) {
            seen.insert(t.videoId)
            out.append(t)
        }
        return out
    }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isLoggedIn, player.favoriteTracks.isEmpty {
                    signedOut
                } else if loading {
                    ScrollView { SkeletonGrid() }
                } else if playlists.isEmpty, likedAll.isEmpty {
                    Text("No favourites yet")
                        .foregroundStyle(palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        if !likedAll.isEmpty {
                            NavigationLink(value: LikedRoute()) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        palette.heroGradient
                                        Image(systemName: "heart.fill")
                                            .font(.blaze(26)).foregroundStyle(.white)
                                    }
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Liked songs")
                                            .font(.blaze(16, .semibold))
                                            .foregroundStyle(palette.onSurface)
                                        Text("\(likedAll.count) songs")
                                            .font(.blaze(13))
                                            .foregroundStyle(palette.onSurfaceVariant)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption).foregroundStyle(palette.onSurface.opacity(0.35))
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                            }
                            .buttonStyle(.plain)
                        }

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(playlists) { item in
                                NavigationLink(value: item) {
                                    LibraryCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .playerBottomInsetArea()
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Your Library")
            .navigationDestination(for: HomeItem.self) { item in
                PlaylistView(item: item, player: player)
            }
            .navigationDestination(for: LikedRoute.self) { _ in
                TrackListView(title: "Liked songs", tracks: likedAll, player: player)
            }
        }
        .sheet(isPresented: $showLogin) { LoginView() }
        .task(id: auth.isLoggedIn) { await load() }
    }

    private var signedOut: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.blaze(48))
                .foregroundStyle(palette.accent)
            Text("Sign in to see your favorites")
                .font(.blaze(16))
                .foregroundStyle(palette.onSurfaceVariant)
            Button { showLogin = true } label: {
                Text("Sign in with Google")
                    .font(.blaze(16, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32).padding(.vertical, 14)
                    .background(palette.heroGradient)
                    .clipShape(Capsule())
            }
        }
    }

    private func load() async {
        guard auth.isLoggedIn else {
            playlists = []
            liked = []
            return
        }
        guard playlists.isEmpty, liked.isEmpty else { return }
        loading = true
        async let playlistsTask = YouTube.libraryPlaylists()
        async let likedTask = YouTube.likedSongs()
        let (p, l) = await (playlistsTask, likedTask)
        await MainActor.run {
            playlists = p
            liked = l
            loading = false
        }
    }
}

/// Navigation marker for the Liked songs list.
struct LikedRoute: Hashable {}

/// A list of tracks. Kept as a thin name over `SongListScreen` so every list in
/// the app — liked, downloaded, cached, top — shares one design.
struct TrackListView: View {
    let title: String
    let tracks: [Track]
    @ObservedObject var player: Player

    var body: some View {
        SongListScreen(title: title, tracks: tracks, player: player)
    }
}

/// A library grid tile: square art + playlist name + subtitle.
private struct LibraryCard: View {
    @Environment(\.palette) private var palette
    let item: HomeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: item.thumbnailURL, size: 180) {
                palette.onSurface.opacity(0.06)
                    .overlay(Image(systemName: "music.note.list")
                        .font(.blaze(36))
                        .foregroundStyle(palette.onSurface.opacity(0.35)))
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(item.title)
                .font(.blaze(14, .semibold))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.blaze(12))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .lineLimit(1)
            }
        }
    }
}
