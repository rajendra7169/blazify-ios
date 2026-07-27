import SwiftUI

/// The Blazify home feed — a faithful SwiftUI port of the BlazePlayer (Flutter)
/// home: custom header, amber greeting card, search pill, and horizontal rails
/// of real YouTube Music recommendations.
struct HomeView: View {
    @ObservedObject var player: Player
    @ObservedObject private var auth = Auth.shared

    @State private var sections: [HomeSection] = []
    @State private var loading = true
    @State private var path = NavigationPath()
    @State private var showLogin = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    GreetingCard()
                    searchPill

                    if loading {
                        ProgressView()
                            .tint(Blaze.amber)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        ForEach(sections) { section in
                            HomeRail(section: section) { tap($0) }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Blaze.scaffold.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeItem.self) { item in
                PlaylistView(item: item, player: player)
            }
            .navigationDestination(for: SearchRoute.self) { _ in
                SearchView(player: player)
            }
        }
        .task {
            if sections.isEmpty { await load() }
        }
        .onChange(of: auth.isLoggedIn) {
            Task { await load() }   // swap to (or from) the personalized feed
        }
        .sheet(isPresented: $showLogin) { LoginView() }
    }

    private func tap(_ item: HomeItem) {
        // A playlist/album opens its detail; a bare song plays immediately.
        if item.browseId != nil {
            path.append(item)
        } else if let vid = item.videoId, !vid.isEmpty {
            player.play([item.asTrack], startAt: 0)
            player.showFullPlayer = true
        }
    }

    private func load() async {
        loading = true
        let s = await YouTube.home()
        await MainActor.run {
            sections = s
            loading = false
        }
    }

    // MARK: - Header (person · logo + wordmark · settings)

    private var header: some View {
        HStack {
            Button {
                if !auth.isLoggedIn { showLogin = true }
            } label: {
                Image(systemName: auth.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(auth.isLoggedIn ? Blaze.amber : .white)
            }
            Spacer()
            HStack(spacing: 8) {
                Image("BlazeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                Text("Blazify")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "gearshape")
                .font(.system(size: 24))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Search pill (opens full search)

    private var searchPill: some View {
        Button {
            path.append(SearchRoute())
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Search songs, albums, artists…")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(Color.white.opacity(0.10))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
            .fill(Blaze.cardGradient)
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
                .foregroundStyle(.white)
                .padding(20)
                .frame(maxWidth: 210, alignment: .leading)
            }
            // Mascot: taller than the card so it overflows the top; bleeds off the
            // right edge; drop shadow gives the 3D "popping out" look.
            .overlay(alignment: .bottomTrailing) {
                Image("HomeHero")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 210)
                    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
                    .offset(x: 16)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)   // reserve room so the hair overflows into the gap
            .padding(.bottom, 8)
    }
}

// MARK: - Rail

/// A titled horizontal rail of cards.
struct HomeRail: View {
    let section: HomeSection
    let onTap: (HomeItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(section.items) { item in
                        MusicCard(item: item) { onTap(item) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// A 140-wide card: art (square or circular) + title + subtitle.
struct MusicCard: View {
    let item: HomeItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                RemoteImage(url: item.thumbnailURL) {
                    Color.white.opacity(0.06)
                        .overlay(
                            Image(systemName: item.isCircular ? "person.fill" : "music.note")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.35)),
                        )
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: item.isCircular ? 70 : 12))
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)

                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(width: 140, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
