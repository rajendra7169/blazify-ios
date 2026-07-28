import SwiftUI

/// The ⋮ player menu (Android's PlayerMenu): track actions in a bottom sheet.
/// Shared by every design so the overflow button behaves identically.
struct PlayerMenuSheet: View {
    @ObservedObject var player: Player
    @ObservedObject private var downloads = Downloads.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAddToPlaylist = false

    var onQueue: () -> Void
    var onSleep: () -> Void
    var onLyrics: () -> Void

    private var downloadState: DownloadState { downloads.state(player.current?.videoId ?? "") }

    var body: some View {
        VStack(spacing: 0) {
            // Track header.
            HStack(spacing: 12) {
                RemoteImage(url: player.current?.artURL(size: 300)) { ArtPlaceholder() }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.current?.title ?? "")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(player.current?.artist ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider().overlay(Color.white.opacity(0.1))

            ScrollView {
                VStack(spacing: 0) {
                    row(player.isCurrentFavorite ? "heart.fill" : "heart",
                        player.isCurrentFavorite ? "Remove from Favorites" : "Add to Favorites",
                        tint: player.isCurrentFavorite ? .red : .white) {
                        player.toggleFavorite()
                    }

                    row(downloadState == .done ? "arrow.down.circle.fill"
                          : downloadState == .downloading ? "hourglass" : "arrow.down.circle",
                        downloadState == .done ? "Remove download"
                          : downloadState == .downloading ? "Downloading…" : "Download for offline",
                        tint: downloadState == .done ? Blaze.amber : .white,
                        disabled: downloadState == .downloading) {
                        if let t = player.current { downloads.toggle(t) }
                    }

                    row("plus.circle", "Add to playlist") { showAddToPlaylist = true }
                    row("quote.bubble", "Lyrics") { dismiss(); onLyrics() }
                    row("list.bullet", "View queue") { dismiss(); onQueue() }
                    row(player.sleepActive ? "moon.zzz.fill" : "moon.zzz",
                        player.sleepActive ? "Sleep timer (on)" : "Sleep timer",
                        tint: player.sleepActive ? Blaze.amber : .white) { dismiss(); onSleep() }

                    if let url = shareURL {
                        ShareLink(item: url) {
                            rowLabel("square.and.arrow.up", "Share", tint: .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(Blaze.surface.ignoresSafeArea())
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAddToPlaylist) {
            if let track = player.current { AddToPlaylistSheet(track: track) }
        }
    }

    private func row(_ icon: String, _ title: String, tint: Color = .white,
                     disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(icon, title, tint: tint) }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
    }

    private func rowLabel(_ icon: String, _ title: String, tint: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(tint)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    private var shareURL: URL? {
        guard let id = player.current?.videoId else { return nil }
        return URL(string: "https://music.youtube.com/watch?v=\(id)")
    }
}
