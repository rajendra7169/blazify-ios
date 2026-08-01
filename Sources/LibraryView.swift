import SwiftUI

/// Library tab: gradient auto-playlist cards,
/// then "Created by you" and "Artists you liked".
struct LibraryView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var auth = Auth.shared
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var cache = AudioCache.shared
    @ObservedObject private var local = LocalMusic.shared

    @State private var playlists: [HomeItem] = []
    @State private var artists: [HomeItem] = []
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
                           thumbs: art(likedTracks),
                           seed: Color(hex: 0xB71C5A), icon: "heart.fill",
                           route: .tracks("Liked", likedTracks))

                    // Content → Show your stats playlists.
                    if ContentPrefs.shared.showStatsPlaylists {
                        banner(title: "Your Top \(PlayHistory.topSize)", subtitle: "",
                               thumbs: art(PlayHistory.top),
                               seed: Color(hex: 0xEF6C00), icon: "chart.line.uptrend.xyaxis",
                               route: .topPlaylist)
                    }

                    HStack(spacing: 12) {
                        BlazePlaylistCard(
                            title: "Cached", subtitle: cacheSize,
                            thumbnails: art(cache.tracks),
                            seed: Color(hex: 0x00838F), aspectRatio: boxRatio,
                            icon: "arrow.triangle.2.circlepath",
                        ) { route = .tracks("Cached", cache.tracks) }

                        BlazePlaylistCard(
                            title: "Downloaded", thumbnails: art(downloads.tracks),
                            seed: Color(hex: 0x283593), aspectRatio: boxRatio, icon: "arrow.down.circle",
                        ) { route = .tracks("Downloaded", downloads.tracks) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    banner(title: "On this phone", subtitle: localSize,
                           thumbs: art(local.tracks),
                           seed: Color(hex: 0x2E7D32), icon: "iphone.gen3",
                           route: .local)


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

                }
                .playerBottomPadding()
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationDestination(item: $route) { LibraryRouteView(route: $0, player: player) }
        }
        .task(id: auth.isLoggedIn) { await load() }
    }

    /// Cover URLs for a card's collage. Resolved rather than raw: a stored
    /// thumbnail can be a dead file:// path from an old container, and artURL
    /// also prefers the copy on disk so the collage survives being offline.
    private func art(_ tracks: [Track]) -> [String] {
        tracks.prefix(4).compactMap { $0.artURL(size: 544)?.absoluteString }
    }

    /// Local favourites merged with the account's liked songs.
    private var likedTracks: [Track] { player.favoriteTracks }

    /// Human-readable cache footprint, e.g. "128 MB". Reads the *published*
    /// size — it used to stat every cached file on each render.
    /// Songs and their size, or an invitation when there aren't any yet.
    private var localSize: String {
        guard !local.tracks.isEmpty else { return String(localized: "Add your own music") }
        let mb = Double(local.sizeBytes) / 1_048_576
        let count = local.tracks.count
        let songs = count == 1 ? String(localized: "1 song") : String(localized: "\(count) songs")
        return mb < 1 ? songs : songs + String(format: " · %.0f MB", mb)
    }

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
            playlists = []; artists = []
            return
        }
        loading = true
        async let p = YouTube.library("FEmusic_liked_playlists")
        async let a = YouTube.library("FEmusic_library_corpus_artists")
        let (pl, ar) = await (p, a)
        await MainActor.run {
            playlists = pl
            artists = ar
            loading = false
        }
    }
}

/// Where a Library or Yours card leads.
enum LibraryRoute: Hashable {
    case tracks(String, [Track])
    case artist(String)
    /// Music imported from Files, which manages its own list.
    case local
    case playlist(HomeItem)
    /// Browse categories, which open filtered collections rather than one list.
    case songs
    case albums
    case artists
    case playlists
    case history
    case stats
    case topPlaylist
}

/// One place that turns a `LibraryRoute` into its screen, so Library, Yours and
/// Stats all navigate identically.
struct LibraryRouteView: View {
    let route: LibraryRoute
    @ObservedObject var player: Player
    // The Songs route snapshots Downloaded and Cached into plain arrays when
    // this body runs, and `.navigationDestination` won't rebuild it just
    // because the parent re-rendered. Without observing these here, a song
    // downloaded while the list is open only appears when some unrelated
    // Player change happens to redraw the screen.
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var cache = AudioCache.shared

    var body: some View {
        switch route {
        case .tracks(let title, let tracks):
            SongListScreen(title: title, tracks: tracks, player: player)
        case .artist(let id):
            ArtistView(browseId: id, player: player)
        case .local:
            LocalMusicView(player: player)
        case .playlist(let item):
            PlaylistView(item: item, player: player)
        case .songs:
            SongListScreen(title: "Songs", filters: SongCategories.filters(player: player),
                           player: player)
        case .albums:
            LibraryCollectionView(kind: .albums, player: player)
        case .artists:
            LibraryCollectionView(kind: .artists, player: player)
        case .playlists:
            LibraryCollectionView(kind: .playlists, player: player)
        case .history:
            HistoryView(player: player)
        case .stats:
            StatsView(player: player)
        case .topPlaylist:
            SongListScreen(title: "Your Top \(PlayHistory.topSize)",
                           filters: SongCategories.topFilters, player: player)
        }
    }
}

/// The capsule filters behind the Songs category
/// (Library / Liked / Downloaded), plus our own on-disk cache and imports.
enum SongCategories {
    static func filters(player: Player) -> [SongListFilter] {
        [
            SongListFilter("Library", PlayHistory.recent),
            SongListFilter("Liked", player.favoriteTracks),
            SongListFilter("Downloaded", Downloads.shared.tracks),
            SongListFilter("Cached", AudioCache.shared.tracks),
            SongListFilter("On this phone", LocalMusic.shared.tracks),
        ]
    }

 /// Top-50 periods for the Top playlist.
    static var topFilters: [SongListFilter] {
        StatPeriod.topFilters.map {
            SongListFilter($0.title, PlayHistory.mostPlayed($0, limit: PlayHistory.topSize))
        }
    }
}
