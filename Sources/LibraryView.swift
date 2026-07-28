import SwiftUI

/// Library tab, ported from BlazeLibraryHome.kt: gradient auto-playlist cards,
/// then "Created by you" and "Artists you liked".
struct LibraryView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var auth = Auth.shared
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var cache = AudioCache.shared

    @State private var playlists: [HomeItem] = []
    @State private var artists: [HomeItem] = []
    @State private var uploaded: [Track] = []
    @State private var loading = false
    @State private var route: LibraryRoute?

    private let longRatio: CGFloat = 2.9    // full-width banners
    private let boxRatio: CGFloat = 1.5     // paired cards
    private let userRatio: CGFloat = 1.55   // created-by-you grid

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 8)

                    banner(title: "Liked", subtitle: "\(likedTracks.count) songs",
                           thumbs: likedTracks.prefix(4).map(\.thumbnail),
                           seed: Color(hex: 0xB71C5A), icon: "heart.fill",
                           route: .tracks("Liked", likedTracks))

                    banner(title: "Your Top 50", subtitle: "",
                           thumbs: PlayHistory.top.prefix(4).map(\.thumbnail),
                           seed: Color(hex: 0xEF6C00), icon: "chart.line.uptrend.xyaxis",
                           route: .tracks("Your Top 50", Array(PlayHistory.top.prefix(50))))

                    HStack(spacing: 12) {
                        BlazePlaylistCard(
                            title: "Cached", subtitle: cacheSize,
                            thumbnails: cache.tracks.prefix(4).map(\.thumbnail),
                            seed: Color(hex: 0x00838F), aspectRatio: boxRatio,
                            icon: "arrow.triangle.2.circlepath",
                        ) { route = .tracks("Cached", cache.tracks) }

                        BlazePlaylistCard(
                            title: "Downloaded", thumbnails: downloads.tracks.prefix(4).map(\.thumbnail),
                            seed: Color(hex: 0x283593), aspectRatio: boxRatio, icon: "arrow.down.circle",
                        ) { route = .tracks("Downloaded", downloads.tracks) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    if auth.isLoggedIn {
                        banner(title: "Uploaded", subtitle: "",
                               thumbs: uploaded.prefix(4).map(\.thumbnail),
                               seed: Color(hex: 0x6A1B9A), icon: "square.and.arrow.up",
                               route: .tracks("Uploaded", uploaded))
                    }

                    if loading { SkeletonGrid(count: 2) }

                    if !playlists.isEmpty {
                        Spacer().frame(height: 8)
                        BlazeSectionHeader(title: "Created by you")
                        createdByYou
                    }

                    if !artists.isEmpty {
                        Spacer().frame(height: 8)
                        BlazeSectionHeader(title: "Artists you liked")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(artists) { artist in
                                    BlazeMusicCard(title: artist.title, subtitle: artist.subtitle,
                                                   thumbnail: artist.thumbnail, isCircular: true,
                                                   fallbackIcon: "person.fill") {
                                        if let id = artist.browseId { route = .artist(id) }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    Spacer().frame(height: 12)
                }
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationDestination(item: $route) { r in
                switch r {
                case .tracks(let title, let tracks):
                    TrackListView(title: title, tracks: tracks, player: player)
                case .artist(let id):
                    ArtistView(browseId: id, player: player)
                case .playlist(let item):
                    PlaylistView(item: item, player: player)
                }
            }
        }
        .task(id: auth.isLoggedIn) { await load() }
    }

    /// Local favourites merged with the account's liked songs.
    private var likedTracks: [Track] { player.favoriteTracks }

    /// Human-readable cache footprint, e.g. "128 MB".
    private var cacheSize: String {
        let mb = Double(cache.sizeBytes) / 1_048_576
        return mb < 1 ? "" : String(format: "%.0f MB", mb)
    }

    private func banner(title: String, subtitle: String, thumbs: [String],
                        seed: Color, icon: String, route destination: LibraryRoute) -> some View {
        BlazePlaylistCard(title: title, subtitle: subtitle, thumbnails: thumbs,
                          seed: seed, aspectRatio: longRatio, icon: icon) {
            route = destination
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var createdByYou: some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: playlists.count, by: 2)), id: \.self) { i in
                HStack(spacing: 12) {
                    BlazePlaylistCard(
                        title: playlists[i].title, subtitle: playlists[i].subtitle,
                        thumbnails: [playlists[i].thumbnail],
                        seed: BlazePalette.color(i), aspectRatio: userRatio,
                    ) { route = .playlist(playlists[i]) }

                    if i + 1 < playlists.count {
                        BlazePlaylistCard(
                            title: playlists[i + 1].title, subtitle: playlists[i + 1].subtitle,
                            thumbnails: [playlists[i + 1].thumbnail],
                            seed: BlazePalette.color(i + 1), aspectRatio: userRatio,
                        ) { route = .playlist(playlists[i + 1]) }
                    } else {
                        Color.clear
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private func load() async {
        guard auth.isLoggedIn else {
            playlists = []; artists = []; uploaded = []
            return
        }
        loading = true
        async let p = YouTube.library("FEmusic_liked_playlists")
        async let a = YouTube.library("FEmusic_library_corpus_artists")
        async let u = YouTube.uploadedSongs()
        let (pl, ar, up) = await (p, a, u)
        await MainActor.run {
            playlists = pl
            artists = ar
            uploaded = up
            loading = false
        }
    }
}

/// Where a Library card leads.
enum LibraryRoute: Hashable {
    case tracks(String, [Track])
    case artist(String)
    case playlist(HomeItem)
}
