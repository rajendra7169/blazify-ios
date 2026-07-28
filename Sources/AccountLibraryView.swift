import SwiftUI

/// The signed-in account's YouTube Music library, ported from AccountScreen.kt:
/// a Playlists / Albums / Artists chip row over an adaptive grid.
struct AccountLibraryView: View {
    @ObservedObject var player: Player
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case playlists = "Playlists"
        case albums = "Albums"
        case artists = "Artists"

        var id: String { rawValue }
        var browseId: String {
            switch self {
            case .playlists: "FEmusic_liked_playlists"
            case .albums: "FEmusic_liked_albums"
            case .artists: "FEmusic_library_corpus_artists"
            }
        }
    }

    @State private var kind: Kind = .playlists
    @State private var items: [HomeItem] = []
    @State private var loading = true

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Kind.allCases) { k in
                            let on = k == kind
                            Text(k.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(on ? .black : .white)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(on ? AnyShapeStyle(Blaze.amber)
                                               : AnyShapeStyle(Color.white.opacity(0.08)))
                                .clipShape(Capsule())
                                .onTapGesture {
                                    kind = k
                                    Task { await load() }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 8)

                if loading {
                    SkeletonGrid()
                } else if items.isEmpty {
                    Text("Nothing here yet")
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            NavigationLink(value: item) { PlaylistGridCard(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .background(theme.scaffold.ignoresSafeArea())
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeItem.self) { item in
                PlaylistView(item: item, player: player)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Blaze.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private func load() async {
        loading = true
        items = []
        let result = await YouTube.library(kind.browseId)
        await MainActor.run {
            items = result
            loading = false
        }
    }
}
