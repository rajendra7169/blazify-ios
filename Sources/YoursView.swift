import SwiftUI

/// "Yours", ported from YoursScreen.kt: Recently Played, Recommended for You,
/// Browse Categories, Your Playlists, Trending, Mood Playlists and Favorite
/// Artists — every rail 16pt inset with 12pt spacing.
struct YoursView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var auth = Auth.shared
    @ObservedObject private var downloads = Downloads.shared

    @State private var accountPlaylists: [HomeItem] = []
    @State private var artists: [HomeItem] = []
    @State private var moods: [MoodItem] = []
    @State private var route: LibraryRoute?
    @State private var moodRoute: MoodItem?
    @State private var loading = false
    @State private var showAccount = false
    @State private var showLogin = false
    @State private var showTogether = false

    /// Trending is what you've played *most*, not most recently — Android reads
    /// this from `mostPlayedSongs`, and "See more" opens the full Stats screen.
    private var trendingSongs: [Track] { PlayHistory.mostPlayed(.all, limit: 12) }
    /// Fresh favourites: the last month's most-played, minus the all-time top.
    private var recommended: [Track] {
        let top = Set(trendingSongs.prefix(6).map(\.videoId))
        return PlayHistory.mostPlayed(.month1, limit: 20)
            .filter { !top.contains($0.videoId) }
            .prefix(15).map { $0 }
    }

    /// Android cycles these glyphs across the mood rail.
    private let moodIcons = ["waveform", "antenna.radiowaves.left.and.right", "slider.horizontal.3",
                             "star.fill", "heart.fill", "moon.zzz.fill", "music.note", "speedometer"]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !PlayHistory.recent.isEmpty {
                        // "See more" opens the full dated history, as Android does.
                        BlazeSectionHeader(title: "Recently Played") { route = .history }
                        rail(PlayHistory.recent.prefix(15).map { $0 }, queueTitle: "Recently Played")
                    }

                    if !recommended.isEmpty {
                        BlazeSectionHeader(title: "Recommended for You")
                        rail(recommended, queueTitle: "Recommended")
                    }

                    BlazeSectionHeader(title: "Browse Categories")
                    categories

                    if !playlistCards.isEmpty {
                        BlazeSectionHeader(title: "Your Playlists") { route = .playlists }
                        playlistRail
                    }

                    if !trendingSongs.isEmpty || !artists.isEmpty {
                        BlazeSectionHeader(title: "Trending") { route = .stats }
                        trendingRail
                    }

                    if !moods.isEmpty {
                        BlazeSectionHeader(title: "Mood Playlists")
                        moodRail
                    }

                    if !artists.isEmpty {
                        BlazeSectionHeader(title: "Favorite Artists")
                        artistRail
                    }

                    if loading { SkeletonRail() }
                    Spacer().frame(height: 12)
                }
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Yours")
            .toolbar {
                // Same pair Android puts in the Yours app bar.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if auth.isLoggedIn { showAccount = true } else { showLogin = true }
                    } label: {
                        Image(systemName: auth.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle")
                            .foregroundStyle(auth.isLoggedIn ? palette.accent : palette.onSurface)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showTogether = true } label: {
                        Image(systemName: "person.2.wave.2.fill")
                            .foregroundStyle(palette.onSurface)
                    }
                }
            }
            .navigationDestination(item: $route) { LibraryRouteView(route: $0, player: player) }
            .navigationDestination(item: $moodRoute) { mood in
                MoodDetailView(mood: mood, player: player)
            }
        }
        .sheet(isPresented: $showLogin) { LoginView() }
        .sheet(isPresented: $showTogether) { TogetherView() }
        .fullScreenCover(isPresented: $showAccount) {
            AccountPopup(player: player, isPresented: $showAccount)
                .presentationBackground(.clear)
        }
        .task(id: auth.isLoggedIn) { await load() }
    }

    // MARK: Rails

    private func rail(_ tracks: [Track], queueTitle: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                    BlazeMusicCard(title: track.title, subtitle: track.artist,
                                   thumbnail: track.thumbnail) {
                        player.play(tracks, startAt: i)
                        player.showFullPlayer = true
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Six square gradient tiles, three per row. Each opens its own collection —
    /// Songs, Albums, Artists and Playlists are filtered browsers; Downloads and
    /// Favorites are auto-playlists, exactly as Android routes them.
    private var categories: some View {
        let items: [(String, String, Color, LibraryRoute)] = [
            ("Songs", "music.note", Color(hex: 0xFF6B6B), .songs),
            ("Albums", "square.stack", Color(hex: 0x4ECDC4), .albums),
            ("Artists", "person.2.fill", Color(hex: 0xFFBE0B), .artists),
            ("Playlists", "list.bullet.rectangle", Color(hex: 0x8B5CF6), .playlists),
            ("Downloads", "arrow.down.circle", Color(hex: 0xEC4899),
             .tracks("Downloads", downloads.tracks)),
            ("Favorites", "heart.fill", Color(hex: 0xEF4444),
             .tracks("Favorites", player.favoriteTracks)),
        ]
        return VStack(spacing: 16) {
            ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { start in
                HStack(spacing: 16) {
                    ForEach(Array(start..<min(start + 3, items.count)), id: \.self) { i in
                        let item = items[i]
                        BlazeCategoryTile(label: item.0, icon: item.1, color: item.2) {
                            route = item.3
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// Favorites first, then the account's playlists — one seed colour, as Android does.
    private var playlistCards: [(title: String, subtitle: String, thumb: String?, item: HomeItem?)] {
        var out: [(String, String, String?, HomeItem?)] = []
        if !player.favoriteTracks.isEmpty {
            out.append(("Favorites", "\(player.favoriteTracks.count) songs",
                        player.favoriteTracks.first?.thumbnail, nil))
        }
        for p in accountPlaylists { out.append((p.title, p.subtitle, p.thumbnail, p)) }
        return out
    }

    private var playlistRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(playlistCards.enumerated()), id: \.offset) { _, card in
                    BlazeGradientCard(title: card.title, subtitle: card.subtitle,
                                      seed: palette.accent, width: 160, height: 160,
                                      icon: card.item == nil ? "heart.fill" : nil) {
                        if let item = card.item {
                            route = .playlist(item)
                        } else {
                            route = .tracks("Favorites", player.favoriteTracks)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Songs and artists interleaved — square, circle, square, circle.
    private var trendingRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                let songs = trendingSongs
                let people = Array(artists.prefix(12))
                ForEach(Array(0..<max(songs.count, people.count)), id: \.self) { i in
                    if i < songs.count {
                        BlazeMusicCard(title: songs[i].title, subtitle: songs[i].artist,
                                       thumbnail: songs[i].thumbnail) {
                            player.play(songs, startAt: i)
                            player.showFullPlayer = true
                        }
                    }
                    if i < people.count {
                        BlazeMusicCard(title: people[i].title, subtitle: people[i].subtitle,
                                       thumbnail: people[i].thumbnail, isCircular: true,
                                       fallbackIcon: "person.fill") {
                            if let id = people[i].browseId { route = .artist(id) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Tall 138×208 gradient cards using YouTube's own stripe colour.
    private var moodRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(moods.prefix(15).enumerated()), id: \.element.id) { i, mood in
                    BlazeGradientCard(title: mood.title, seed: Color(hex: mood.colorARGB & 0xFFFFFF),
                                      width: 138, height: 208,
                                      icon: moodIcons[i % moodIcons.count]) {
                        moodRoute = mood
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var artistRail: some View {
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

    private func load() async {
        loading = true
        async let moodsTask = YouTube.moods()
        let m = await moodsTask
        var pl: [HomeItem] = []
        var ar: [HomeItem] = []
        if auth.isLoggedIn {
            async let p = YouTube.library("FEmusic_liked_playlists")
            async let a = YouTube.library("FEmusic_library_corpus_artists")
            (pl, ar) = await (p, a)
        }
        await MainActor.run {
            moods = m
            accountPlaylists = pl
            artists = ar
            loading = false
        }
    }
}
