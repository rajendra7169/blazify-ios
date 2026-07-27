import SwiftUI

/// Favorites tab: the signed-in user's saved & created playlists, tap to open.
struct FavoritesView: View {
    @ObservedObject private var auth = Auth.shared
    @ObservedObject var player: Player

    @State private var playlists: [HomeItem] = []
    @State private var loading = false
    @State private var showLogin = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isLoggedIn {
                    signedOut
                } else if loading {
                    ProgressView().tint(Blaze.amber)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if playlists.isEmpty {
                    Text("No playlists yet")
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
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
            .background(Blaze.scaffold.ignoresSafeArea())
            .navigationTitle("Your Library")
            .navigationDestination(for: HomeItem.self) { item in
                PlaylistView(item: item, player: player)
            }
        }
        .sheet(isPresented: $showLogin) { LoginView() }
        .task(id: auth.isLoggedIn) { await load() }
    }

    private var signedOut: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(Blaze.amber)
            Text("Sign in to see your favorites")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
            Button { showLogin = true } label: {
                Text("Sign in with Google")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32).padding(.vertical, 14)
                    .background(Blaze.gradient)
                    .clipShape(Capsule())
            }
        }
    }

    private func load() async {
        guard auth.isLoggedIn else {
            playlists = []
            return
        }
        guard playlists.isEmpty else { return }
        loading = true
        let p = await YouTube.libraryPlaylists()
        await MainActor.run {
            playlists = p
            loading = false
        }
    }
}

/// A library grid tile: square art + playlist name + subtitle.
private struct LibraryCard: View {
    let item: HomeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: item.thumbnailURL) {
                Color.white.opacity(0.06)
                    .overlay(Image(systemName: "music.note.list")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.35)))
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }
}
