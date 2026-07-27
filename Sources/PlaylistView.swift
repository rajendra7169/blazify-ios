import SwiftUI

/// A playlist or album opened from a home card: big art header, Play / Shuffle
/// actions, then the track list. Tapping any row starts playback from there.
struct PlaylistView: View {
    let item: HomeItem
    @ObservedObject var player: Player

    @State private var tracks: [Track] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AsyncImage(url: item.thumbnailURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.white.opacity(0.06)
                        .overlay(Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.35)))
                }
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 12)
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                if !tracks.isEmpty {
                    HStack(spacing: 12) {
                        actionButton("Play", "play.fill") { player.play(tracks, startAt: 0); player.showFullPlayer = true }
                        actionButton("Shuffle", "shuffle") {
                            player.play(tracks.shuffled(), startAt: 0); player.showFullPlayer = true
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if loading {
                    ProgressView().tint(Blaze.amber).padding(.top, 40)
                } else if tracks.isEmpty {
                    Text("Nothing to play here")
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { pair in
                            Button {
                                player.play(tracks, startAt: pair.offset)
                                player.showFullPlayer = true
                            } label: {
                                TrackRow(track: pair.element)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Blaze.scaffold.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func actionButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Blaze.gradient)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        loading = true
        let t = await YouTube.playlist(browseId: item.browseId ?? "")
        await MainActor.run {
            tracks = t
            loading = false
        }
    }
}
