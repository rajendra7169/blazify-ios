import SwiftUI

/// "Yours", ported from YoursScreen.kt: Recently Played, Recommended for You,
/// Browse Categories, Your Playlists, Trending, Mood Playlists and Favorite
/// Artists — every rail 16pt inset with 12pt spacing.
struct YoursView: View {
    @ObservedObject var player: Player
    @ObservedObject private var theme = AppTheme.shared
    @ObservedObject private var auth = Auth.shared
    @ObservedObject private var downloads = Downloads.shared

    @State private var accountPlaylists: [HomeItem] = []
    @State private var artists: [HomeItem] = []
    @State private var moods: [MoodItem] = []
    @State private var route: LibraryRoute?
    @State private var moodRoute: MoodItem?
    @State private var loading = false

    /// Android cycles these glyphs across the mood rail.
    private let moodIcons = ["waveform", "antenna.radiowaves.left.and.right", "slider.horizontal.3",
                             "star.fill", "heart.fill", "moon.zzz.fill", "music.note", "speedometer"]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !PlayHistory.recent.isEmpty {
                        BlazeSectionHeader(title: "Recently Played") {
                            route = .tracks("Recently Played", PlayHistory.recent)
                        }
                        rail(PlayHistory.recent.prefix(15).map { $0 }, queueTitle: "Recently Played")
                    }

                    if !PlayHistory.top.isEmpty {
                        BlazeSectionHeader(title: "Recommended for You")
                        rail(PlayHistory.top.prefix(15).map { $0 }, queueTitle: "Recommended")
                    }

                    BlazeSectionHeader(title: "Browse Categories")
                    categories

                    if !playlistCards.isEmpty {
                        BlazeSectionHeader(title: "Your Playlists")
                        playlistRail
                    }

                    if !PlayHistory.top.isEmpty || !artists.isEmpty {
                        BlazeSectionHeader(title: "Trending")
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
            .background(theme.scaffold.ignoresSafeArea())
            .navigationTitle("Yours")
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
            .navigationDestination(item: $moodRoute) { mood in
                MoodDetailView(mood: mood, player: player)
            }
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

    /// Six square gradient tiles, three per row.
    private var categories: some View {
        let items: [(String, String, Color, LibraryRoute)] = [
            ("Songs", "music.note", Color(hex: 0xFF6B6B), .tracks("Songs", PlayHistory.recent)),
            ("Albums", "square.stack", Color(hex: 0x4ECDC4), .tracks("Albums", [])),
            ("Artists", "person.2.fill", Color(hex: 0xFFBE0B), .tracks("Artists", [])),
            ("Playlists", "list.bullet.rectangle", Color(hex: 0x8B5CF6), .tracks("Playlists", [])),
            ("Downloads", "arrow.down.circle", Color(hex: 0xEC4899), .tracks("Downloads", downloads.tracks)),
            ("Favorites", "heart.fill", Color(hex: 0xEF4444), .tracks("Favorites", player.favoriteTracks)),
        ]
        return VStack(spacing: 16) {
            ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { start in
                HStack(spacing: 16) {
                    ForEach(start..<min(start + 3, items.count), id: \.self) { i in
                        let item = items[i]
                        BlazeCategoryTile(label: item.0, icon: item.1, color: item.2) {
                            switch item.0 {
                            case "Artists": if let first = artists.first, let id = first.browseId { route = .artist(id) }
                            case "Playlists": if let first = accountPlaylists.first { route = .playlist(first) }
                            default: route = item.3
                            }
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
                                      seed: theme.accent, width: 160, height: 160,
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
                let songs = Array(PlayHistory.top.prefix(12))
                let people = Array(artists.prefix(12))
                ForEach(0..<max(songs.count, people.count), id: \.self) { i in
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
