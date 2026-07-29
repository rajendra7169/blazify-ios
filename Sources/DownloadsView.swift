import SwiftUI

/// The offline library — every downloaded track, plays with no network.
struct DownloadsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var downloads = Downloads.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if downloads.tracks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 44)).foregroundStyle(palette.accent)
                        Text("No downloads yet").foregroundStyle(palette.onSurfaceVariant)
                        Text("Tap ⋮ → Download on a song, or Download on a playlist.")
                            .font(.caption).foregroundStyle(palette.onSurfaceVariant)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(downloads.tracks.enumerated()), id: \.element.id) { pair in
                            SongRow(track: pair.element, player: player,
                                    trailingPadding: 0) {
                                player.play(downloads.tracks, startAt: pair.offset)
                                player.showFullPlayer = true
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .swipeActions {
                                Button(role: .destructive) {
                                    downloads.remove(pair.element.videoId)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(palette.accent)
                }
            }
        }
    }
}
