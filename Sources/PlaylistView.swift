import SwiftUI

/// A playlist or album opened from a home card: big art header, Play / Shuffle
/// actions, then the track list. Tapping any row starts playback from there.
struct PlaylistView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var theme = AppTheme.shared
    let item: HomeItem
    @ObservedObject var player: Player
    @ObservedObject private var downloads = Downloads.shared

    @State private var tracks: [Track] = []
    @State private var loading = true

    private var downloadLabel: String {
        guard !tracks.isEmpty else { return "Download" }
        let done = tracks.filter { downloads.isDownloaded($0.videoId) }.count
        if done == tracks.count { return "Downloaded" }
        if done > 0 { return "\(done)/\(tracks.count)" }
        return "Download"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RemoteImage(url: item.thumbnailURL) {
                    palette.onSurface.opacity(0.06)
                        .overlay(Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundStyle(palette.onSurface.opacity(0.35)))
                }
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 12)
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                        .multilineTextAlignment(.center)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                if !tracks.isEmpty {
                    HStack(spacing: 10) {
                        actionButton("Play", "play.fill") { player.play(tracks, startAt: 0); player.showFullPlayer = true }
                        actionButton("Shuffle", "shuffle") {
                            player.play(tracks.shuffled(), startAt: 0); player.showFullPlayer = true
                        }
                        actionButton(downloadLabel, "arrow.down.circle") {
                            Downloads.shared.downloadAll(tracks)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if loading {
                    SkeletonTrackList(rows: 7).padding(.top, 8)
                } else if tracks.isEmpty {
                    Text("Nothing to play here")
                        .foregroundStyle(palette.onSurfaceVariant)
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
        .background(theme.scaffold.ignoresSafeArea())
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
            .background(palette.heroGradient)
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
