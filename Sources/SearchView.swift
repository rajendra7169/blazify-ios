import SwiftUI

struct SearchView: View {
    @ObservedObject private var theme = AppTheme.shared
    @ObservedObject var player: Player

    @State private var query = ""
    @State private var results: [Track] = []
    @State private var searching = false
    @State private var didSearch = false

    var body: some View {
        List {
            ForEach(Array(results.enumerated()), id: \.element.id) { pair in
                Button {
                    player.play(results, startAt: pair.offset)
                    player.showFullPlayer = true
                } label: {
                    TrackRow(track: pair.element)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.scaffold.ignoresSafeArea())
        .overlay {
            if searching {
                ScrollView { SkeletonTrackList(rows: 8).padding(.top, 8) }
            } else if results.isEmpty {
                Text(didSearch ? "No results" : "Search for a song")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Blazify")
        .searchable(text: $query, prompt: "Songs, artists…")
        .onSubmit(of: .search) { runSearch() }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        didSearch = true
        Task {
            let r = await YouTube.search(q)
            await MainActor.run {
                results = r
                searching = false
            }
        }
    }
}

/// One search-result row: art, title, artist.
struct TrackRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: track.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.white.opacity(0.1)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.subheadline).foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
