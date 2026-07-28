import SwiftUI

/// Albums, Artists or Playlists from the account's library — the screens behind
/// the Yours browse-category tiles. Playlists get the same wide gradient cards
/// as the Library tab; albums and artists get a grid.
struct LibraryCollectionView: View {
    enum Kind {
        case albums, artists, playlists

        var title: String {
            switch self {
            case .albums: "Albums"
            case .artists: "Artists"
            case .playlists: "Playlists"
            }
        }

        /// Android browses these same three library corpora.
        var browseId: String {
            switch self {
            case .albums: "FEmusic_liked_albums"
            case .artists: "FEmusic_library_corpus_artists"
            case .playlists: "FEmusic_liked_playlists"
            }
        }
    }

    @Environment(\.palette) private var palette
    let kind: Kind
    @ObservedObject var player: Player
    @ObservedObject private var auth = Auth.shared

    @State private var items: [HomeItem] = []
    @State private var loading = true
    @State private var route: LibraryRoute?
    @State private var query = ""
    @State private var searching = false

    private var shown: [HomeItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.title.lowercased().contains(q) }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if loading {
                    SkeletonGrid(count: 4)
                } else if shown.isEmpty {
                    Text(auth.isLoggedIn
                         ? "Nothing in your \(kind.title.lowercased()) yet."
                         : "Sign in to see your \(kind.title.lowercased()).")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if kind == .playlists {
                    playlistCards
                } else {
                    grid
                }
            }
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { searching.toggle() }
                    if !searching { query = "" }
                } label: {
                    Image(systemName: searching ? "xmark" : "magnifyingglass")
                        .foregroundStyle(palette.onSurface)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if searching {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(palette.onSurfaceVariant)
                    TextField("Search \(kind.title.lowercased())", text: $query)
                        .foregroundStyle(palette.onSurface)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(palette.surfaceHigh)
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(palette.scaffold)
            }
        }
        .navigationDestination(item: $route) { LibraryRouteView(route: $0, player: player) }
        .task(id: auth.isLoggedIn) {
            loading = true
            let result = await YouTube.library(kind.browseId)
            await MainActor.run {
                items = result.filter { $0.browseId != "SE" }
                loading = false
            }
        }
    }

    /// Two-up gradient cards, matching the Library tab's "Created by you".
    private var playlistCards: some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { i in
                HStack(spacing: 12) {
                    BlazePlaylistCard(
                        title: shown[i].title, subtitle: shown[i].subtitle,
                        thumbnails: [shown[i].thumbnail],
                        seed: BlazePalette.color(i), aspectRatio: 1.55,
                    ) { route = .playlist(shown[i]) }

                    if i + 1 < shown.count {
                        BlazePlaylistCard(
                            title: shown[i + 1].title, subtitle: shown[i + 1].subtitle,
                            thumbnails: [shown[i + 1].thumbnail],
                            seed: BlazePalette.color(i + 1), aspectRatio: 1.55,
                        ) { route = .playlist(shown[i + 1]) }
                    } else {
                        Color.clear
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 8)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(shown) { item in
                Button {
                    if kind == .artists, let id = item.browseId {
                        route = .artist(id)
                    } else {
                        route = .playlist(item)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        RemoteImage(url: item.thumbnailURL) {
                            palette.onSurface.opacity(0.06)
                                .overlay(Image(systemName: kind == .artists ? "person.fill" : "square.stack")
                                    .font(.system(size: 36))
                                    .foregroundStyle(palette.onSurface.opacity(0.35)))
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: kind == .artists ? 999 : 12))

                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                            .lineLimit(1)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.onSurfaceVariant)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}
