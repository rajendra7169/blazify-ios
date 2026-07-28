import SwiftUI

/// A Mood/Genre page: the playlists inside a mood tile, in a 2-column grid.
struct MoodDetailView: View {
    let mood: MoodItem
    @ObservedObject var player: Player

    @State private var playlists: [HomeItem] = []
    @State private var loading = true

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if loading {
                SkeletonGrid()
            } else if playlists.isEmpty {
                Text("Nothing here")
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(playlists) { item in
                        // Resolves to the home stack's HomeItem destination (PlaylistView).
                        NavigationLink(value: item) { PlaylistGridCard(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(Blaze.scaffold.ignoresSafeArea())
        .navigationTitle(mood.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let p = await YouTube.moodPlaylists(browseId: mood.browseId ?? "", params: mood.params)
            await MainActor.run {
                playlists = p
                loading = false
            }
        }
    }
}
