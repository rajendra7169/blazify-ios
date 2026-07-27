import SwiftUI

/// The offline library — every downloaded track, plays with no network.
struct DownloadsView: View {
    @ObservedObject var player: Player
    @ObservedObject private var downloads = Downloads.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if downloads.tracks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 44)).foregroundStyle(Blaze.amber)
                        Text("No downloads yet").foregroundStyle(.white.opacity(0.75))
                        Text("Tap ⋮ → Download on a song, or Download on a playlist.")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(downloads.tracks.enumerated()), id: \.element.id) { pair in
                            Button {
                                player.play(downloads.tracks, startAt: pair.offset)
                                player.showFullPlayer = true
                            } label: {
                                TrackRow(track: pair.element)
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
            .background(Blaze.scaffold.ignoresSafeArea())
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Blaze.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
