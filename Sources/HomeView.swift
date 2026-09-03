import SwiftUI

/// The Blazify home feed — a faithful SwiftUI port of the BlazePlayer (Flutter)
/// home: custom header, amber greeting card, search pill, and horizontal rails
/// of real YouTube Music recommendations.
struct HomeView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    /// Lets the search pill switch to Explore, so its tab lights up rather than
    /// pushing a copy of the search page on top of Home.
    @Binding var tab: BlazeTab
    @ObservedObject private var auth = Auth.shared
    @ObservedObject private var look = LookFeel.shared
    @ObservedObject private var net = Reachability.shared
    // Observed so the offline rails refresh the moment a download lands.
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var cache = AudioCache.shared

    @State private var feed = HomeFeed.empty
    @State private var moods: [MoodItem] = []
    @State private var selectedChip: HomeChip?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var localSections: [HomeSection] = []
    @State private var path = NavigationPath()
    @State private var showLogin = false
    @State private var showAccount = false
    @State private var showSettings = false
    @State private var showRecognition = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    // Both are optional from Look & Feel > Home.
                    if look.showHomeGreeting { GreetingCard() }
                    if look.showHomeSearchBar { searchPill }

                    if !net.isOnline {
                        offlineFeed
                    } else {
                        if !feed.chips.isEmpty {
                            ChipsRow(chips: feed.chips, selected: selectedChip) { selectChip($0) }
                        }

                        if loading {
                            SkeletonRail()
                            SkeletonRail()
                        } else {
                            // Locally-derived rails first, reshuffled on every load —
 // this is what makes the feed differ each time, as the
                            // `.shuffled()` sections do.
                            ForEach(localSections) { section in
                                if section.isSongs {
                                    QuickPicksGrid(section: section, player: player)
                                } else {
                                    HomeRail(section: section) { tap($0, within: $1) }
                                }
                            }

                            ForEach(feed.sections) { section in
                                if section.isSongs {
                                    QuickPicksGrid(section: section, player: player)
                                } else {
                                    HomeRail(section: section) { tap($0, within: $1) }
                                }
                            }

                            if !moods.isEmpty {
                                MoodTiles(moods: moods) { path.append($0) }
                            }

                            // Reaching this marker means we're near the end: pull the
 // next page of shelves in, by watching the last visible
                            // index. The `.id` makes SwiftUI build a *new*
                            // marker per token — otherwise the old one stays on screen,
                            // never re-appears, and loading stops after one page.
                            if let token = feed.continuation {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                                    .id(token)
                                    .onAppear { loadMore() }
                            }
                        }
                    }
                }
                .playerBottomPadding()
            }
            .refreshable { await load(reshuffle: true) }
            .background(palette.scaffold.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeItem.self) { item in
                PlaylistView(item: item, player: player)
            }
            .navigationDestination(for: MoodItem.self) { mood in
                MoodDetailView(mood: mood, player: player)
            }
            .navigationDestination(for: SearchRoute.self) { _ in
                SearchView(player: player, pushed: true)
            }
        }
        .task {
            if feed.sections.isEmpty { await load() }
        }
        // Coming back online, pull the real feed in straight away.
        .onChange(of: net.isOnline) {
            if net.isOnline { Task { await load() } }
        }
        .onChange(of: auth.isLoggedIn) {
            Task { await load() }   // swap to (or from) the personalized feed
        }
        .sheet(isPresented: $showLogin) { LoginView() }
        .sheet(isPresented: $showSettings) { SettingsView(player: player) }
        // The account popup's Settings row asks us to open it.
        .onReceive(NotificationCenter.default.publisher(for: .openBlazifySettings)) { _ in
            showSettings = true
        }
        .fullScreenCover(isPresented: $showAccount) {
            AccountPopup(player: player, isPresented: $showAccount)
                .presentationBackground(.clear)
        }
        .fullScreenCover(isPresented: $showRecognition) {
            RecognitionView(player: player)
        }
    }

    private func tap(_ item: HomeItem, within row: [HomeItem] = []) {
        // A playlist/album opens its detail; a bare song plays immediately.
        guard item.browseId == nil else {
            path.append(item)
            return
        }
        guard let vid = item.videoId, !vid.isEmpty else { return }

        // Queue the row it came from rather than the one card. Tapping the
        // third song of a shelf and hearing it stop dead is the whole
        // complaint: there was never a queue to move on to, and the radio
        // that would have rescued it only runs once the queue empties, which
        // for one song means immediately and audibly.
        let songs = row.filter { $0.browseId == nil && !($0.videoId ?? "").isEmpty }
        let start = songs.firstIndex { $0.videoId == vid } ?? 0
        let tracks = songs.isEmpty ? [item.asTrack] : songs.map(\.asTrack)

        player.play(tracks, startAt: songs.isEmpty ? 0 : start)
        player.showFullPlayer = true
    }

    private func load(reshuffle: Bool = false) async {
        // No point firing four requests that can only time out.
        guard net.isOnline else {
            await MainActor.run { loading = false }
            return
        }
        if !reshuffle { loading = true }   // pull-to-refresh has its own spinner
        let seeds = Self.seedPool(player: player)
        async let feedTask = YouTube.home(params: selectedChip?.params)
        async let moodsTask = YouTube.moods()
        async let dynamicTask = Self.buildDynamicSections(seeds: seeds)
        let (f, m, dynamic) = await (feedTask, moodsTask, dynamicTask)
        await MainActor.run {
            // A refresh fires several requests at once and YouTube sometimes
            // answers the home browse with nothing. Keep what we already have
            // rather than blanking the feed down to the local rails.
            if !f.sections.isEmpty { feed = f }
            let shuffle = ContentPrefs.shared.randomizeHomeOrder
            if !m.isEmpty { moods = shuffle ? m.shuffled() : m }
            // Shuffle the running order too, so it isn't always Quick picks on
            // top — the section that leads changes between refreshes.
            // Settings → Content → Shuffle the section order.
            let local = Self.buildLocalSections(player: player) + dynamic
            localSections = shuffle ? local.shuffled() : local
            loading = false
        }
    }

    /// Append the next page of YouTube shelves.
    private func loadMore() {
        guard PlaybackPrefs.shared.autoLoadMore else { return }
        guard let token = feed.continuation, !loadingMore else { return }
        loadingMore = true
        Task {
            let next = await YouTube.home(continuation: token)
            await MainActor.run {
                // Don't repeat a shelf we already have on screen.
                let existing = Set(feed.sections.map(\.title))
                feed.sections += next.sections.filter { !existing.contains($0.title) }
                feed.continuation = next.continuation
                loadingMore = false
            }
        }
    }

    /// Rails generated from a handful of *randomly chosen* songs you like. Each
    /// seed's Related page gives fresh songs, and the section is titled after the
    /// seed — so both the content and the headings change on every refresh, which
 /// is what Daily Discover and "Similar to X" do.
    /// Pick the seeds on the main actor — `favoriteTracks` and the PlayHistory
    /// cache are both main-thread state, so the async fan-out must not touch them.
    @MainActor
    private static func seedPool(player: Player) -> [Track] {
        var pool = player.favoriteTracks + PlayHistory.recent
        var seenIds = Set<String>()
        // An imported file has no catalogue id, so it can't seed a radio.
        pool = pool.filter {
            !$0.videoId.isEmpty && !LocalMusic.isLocal($0.videoId)
                && seenIds.insert($0.videoId).inserted
        }
        return Array(pool.shuffled().prefix(3))
    }

    private static func buildDynamicSections(seeds: [Track]) async -> [HomeSection] {
        guard !seeds.isEmpty else { return [] }
        var sections: [HomeSection] = []
        var discover: [HomeItem] = []

        await withTaskGroup(of: (Track, [HomeSection]).self) { group in
            for seed in seeds {
                group.addTask { (seed, await YouTube.related(videoId: seed.videoId)) }
            }
            for await (seed, related) in group {
                guard let songs = related.first(where: { $0.isSongs }), songs.items.count >= 4 else { continue }
                let picked = songs.items.shuffled()
                discover += picked.prefix(5)
                sections.append(HomeSection(title: "Similar to \(seed.title)",
                                            items: Array(picked.prefix(12)), isSongs: false))
            }
        }

        if discover.count >= 4 {
            var unique = Set<String>()
            let mixed = discover.shuffled().filter { unique.insert($0.videoId ?? $0.title).inserted }
            sections.insert(HomeSection(title: "Daily discover",
                                        items: Array(mixed.prefix(16)), isSongs: true), at: 0)
        }
        return sections
    }

    /// Rails built from what you've actually listened to, shuffled so the home
 /// feed looks different every time — Quick picks / Keep listening
    /// / Forgotten favourites, which are all `.shuffled().take(n)` locally.
    private static func buildLocalSections(player: Player) -> [HomeSection] {
        var out: [HomeSection] = []

        // Songs imported from Files have no place in the online feed — they
        // aren't part of the catalogue and can't seed a radio. They get their
        // own shelf, and only when there's no network to fill Home with.
        func catalogue(_ tracks: [Track]) -> [Track] {
            tracks.filter { !LocalMusic.isLocal($0.videoId) }
        }

        let quick = catalogue(PlayHistory.mostPlayed(.month1, limit: 40)).shuffled().prefix(20)
        if quick.count >= 4 {
            out.append(HomeSection(title: "Quick picks",
                                   items: quick.map(\.asHomeItem), isSongs: true))
        }

        let keep = catalogue(PlayHistory.recent).prefix(40).shuffled().prefix(15)
        if keep.count >= 4 {
            out.append(HomeSection(title: "Keep listening",
                                   items: keep.map(\.asHomeItem), isSongs: false))
        }

 // Liked a while ago but not played recently.
        let recentIds = Set(PlayHistory.recent.prefix(20).map(\.videoId))
        let forgotten = catalogue(player.favoriteTracks)
            .filter { !recentIds.contains($0.videoId) }
            .shuffled().prefix(15)
        if forgotten.count >= 4 {
            out.append(HomeSection(title: "Forgotten favourites",
                                   items: forgotten.map(\.asHomeItem), isSongs: false))
        }
        return out
    }

    // MARK: - Offline

    /// What Home shows with no connection: a notice, then only music that will
    /// actually play from this device.
    @ViewBuilder private var offlineFeed: some View {
        OfflineNotice { Task { await load() } }

        let sections = Self.offlineSections(player: player)
        if sections.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(palette.accent)
                Text("Nothing saved yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                Text("Download songs while you're online and they'll be waiting here.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 56)
        } else {
            ForEach(sections) { section in
                if section.isSongs {
                    QuickPicksGrid(section: section, player: player)
                } else {
                    HomeRail(section: section) { tap($0, within: $1) }
                }
            }
        }
    }

    /// Offline rails, in the order YouTube Music puts them: what you saved
    /// first, then what you reach for. Every rail is filtered to songs whose
    /// audio is on the device — a rail of taps that error is worse than no
    /// rail — and any that comes up empty is dropped rather than left blank.
    @MainActor
    private static func offlineSections(player: Player) -> [HomeSection] {
        func playable(_ tracks: [Track]) -> [Track] {
            var seen = Set<String>()
            return tracks.filter {
                guard !$0.videoId.isEmpty, seen.insert($0.videoId).inserted else { return false }
                return Downloads.shared.isDownloaded($0.videoId)
                    || AudioCache.shared.isCached($0.videoId)
            }
        }

        var out: [HomeSection] = []

        let downloaded = Downloads.shared.tracks
        if !downloaded.isEmpty {
            out.append(HomeSection(title: "Downloaded",
                                   items: downloaded.map(\.asHomeItem), isSongs: true))
        }

        // Your own files need no network at all, so with no signal they're the
        // most useful thing on the screen.
        let own = LocalMusic.shared.tracks
        if !own.isEmpty {
            out.append(HomeSection(title: "On this phone",
                                   items: own.map(\.asHomeItem), isSongs: true))
        }

        let recent = Array(playable(PlayHistory.recent).prefix(20))
        if !recent.isEmpty {
            out.append(HomeSection(title: "Recently played",
                                   items: recent.map(\.asHomeItem), isSongs: false))
        }

        let liked = Array(playable(player.favoriteTracks).prefix(20))
        if !liked.isEmpty {
            out.append(HomeSection(title: "Your favourites",
                                   items: liked.map(\.asHomeItem), isSongs: false))
        }

        let top = Array(playable(PlayHistory.mostPlayed(.all, limit: 80)).prefix(20))
        if !top.isEmpty {
            out.append(HomeSection(title: "Most played",
                                   items: top.map(\.asHomeItem), isSongs: false))
        }
        return out
    }

    private func selectChip(_ chip: HomeChip) {
        guard chip.title != selectedChip?.title else { return }
        selectedChip = chip
        Task {
            loading = true
            let f = await YouTube.home(params: chip.params)
            await MainActor.run {
                feed = f
                loading = false
            }
        }
    }

    // MARK: - Header (person · logo + wordmark · settings)

    private var header: some View {
        HStack {
            Button {
                if auth.isLoggedIn { showAccount = true } else { showLogin = true }
            } label: {
                Image(systemName: auth.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(auth.isLoggedIn ? palette.accent : palette.onSurface)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(bundleImage: "blaze_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                Text("Blazify")
                    .font(.system(size: 24, weight: .bold))
                    // Letter-spaced wordmark, so it reads B l a z i f y. The
                    // trailing space keeps the last letter's tracking from
                    // pushing the text off-centre.
                    .tracking(4)
                    .foregroundStyle(palette.onSurface)
                    .padding(.leading, 4)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel("Settings")
                    .font(.system(size: 24))
                    // Accent, so it follows the palette and the album-art
                    // colour like the rest of the app's action icons.
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 0)
    }

    // MARK: - Search pill (opens full search)

    private var searchPill: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(palette.onSurfaceVariant)
            Text("Search songs, albums, artists…")
                .font(.system(size: 15))
                .foregroundStyle(palette.onSurfaceVariant)
                .lineLimit(1)
            Spacer(minLength: 0)
 // Song recognition, exactly where the header puts the mic.
            Button { showRecognition = true } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(palette.onSurface.opacity(0.10))
        .clipShape(Capsule())
        // Tapping the bar itself opens Explore; only the mic is separate.
        .contentShape(Capsule())
        .onTapGesture { tab = .explore }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

/// Navigation marker so the home search pill can push the search screen.
struct SearchRoute: Hashable {}

// MARK: - Greeting card

/// Amber gradient greeting card (Flutter FeaturedAlbumCard): time-aware greeting
/// on two lines, name, tagline, and the Blaze mascot overflowing the card's top —
/// her hair pokes out above the card with a soft 3D drop shadow.
struct GreetingCard: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var auth = Auth.shared

    private var greeting: (line1: String, line2: String) {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return ("Good", "Morning 🌅")
        case 12..<17: return ("Good", "Afternoon ☀️")
        case 17..<21: return ("Good", "Evening 🌆")
        default: return ("Good", "Night 🌙")
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(palette.heroGradient)
            .frame(height: 160)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting.line1)
                        .font(.system(size: 24, weight: .bold))
                    Text(greeting.line2)
                        .font(.system(size: 24, weight: .bold))
                    Text(auth.accountName ?? "Music Lover")
                        .font(.system(size: 22, weight: .bold))
                        .opacity(0.95)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                        .padding(.top, 2)
                    Text("Enjoy the music 🎵")
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.85)
                        .padding(.top, 2)
                }
                // Sits on the accent gradient, so it stays white in both themes.
                .foregroundStyle(.white)
                .padding(20)
                .frame(maxWidth: 210, alignment: .leading)
            }
            // Mascot: taller than the card so it overflows the top; bleeds off the
            // right edge; drop shadow gives the 3D "popping out" look.
            .overlay(alignment: .bottomTrailing) {
                Image(bundleImage: "blaze_hero")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 216)
                    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
                    .offset(x: 8)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)   // card sits higher; mascot hair reaches the wordmark
            .padding(.bottom, 8)
    }
}

// MARK: - Rail

/// A titled horizontal rail of cards.
struct HomeRail: View {
    @Environment(\.palette) private var palette
    let section: HomeSection
    /// The row is handed over with the card, so tapping one song can queue the
    /// rest of what it was sitting in.
    let onTap: (HomeItem, [HomeItem]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(section.items) { item in
                        MusicCard(item: item) { onTap(item, section.items) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// A 140-wide card: art (square or circular) + title + subtitle.
struct MusicCard: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var look = LookFeel.shared
    let item: HomeItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                RemoteImage(url: item.thumbnailURL, size: look.gridItemSize.cardWidth) {
                    palette.onSurface.opacity(0.06)
                        .overlay(
                            Image(systemName: item.isCircular ? "person.fill" : "music.note")
                                .font(.system(size: 40))
                                .foregroundStyle(palette.onSurface.opacity(0.35)),
                        )
                }
                .frame(width: look.gridItemSize.cardWidth, height: look.gridItemSize.cardWidth)
                .clipShape(RoundedRectangle(cornerRadius: item.isCircular ? 70 : 12))
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)

                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(width: look.gridItemSize.cardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// The banner Home shows with no connection, in the app's own colours.
private struct OfflineNotice: View {
    @Environment(\.palette) private var palette
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're offline")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                Text("Showing music saved on this device")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            Button(action: retry) {
                Text("Retry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(palette.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}
