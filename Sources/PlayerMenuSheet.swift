import SwiftUI

/// The ⋮ player menu (the PlayerMenu): track actions in a bottom sheet.
/// Shared by every design so the overflow button behaves identically.
struct PlayerMenuSheet: View {
    @ObservedObject var player: Player
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var dial = SpeedDial.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAddToPlaylist = false
    @State private var showRepeatTimes = false

    var onQueue: () -> Void
    var onSleep: () -> Void
    var onLyrics: () -> Void
    /// Opened from here because lyrics settings are the ones you actually want
    /// to change while a song is playing and the words are in front of you.
    var onLyricsSettings: () -> Void
    var onLyricsTiming: () -> Void
    var onEqualizer: () -> Void

    private var downloadState: DownloadState { downloads.state(player.current?.videoId ?? "") }

    var body: some View {
        VStack(spacing: 0) {
            // Track header.
            HStack(spacing: 12) {
                RemoteImage(url: player.current?.artURL(size: 300), size: 52) { ArtPlaceholder() }
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
                        // A broadcast has no file to keep: it is a playlist that
                        // keeps growing, and never the same twice.
                        disabled: downloadState == .downloading || player.isCurrentLive) {
                        if let t = player.current { downloads.toggle(t) }
                    }

                    row(player.repeatTimesLeft > 0 ? "repeat.1.circle.fill" : "repeat.1",
                        player.repeatTimesLeft > 0
                            ? String(localized: "\(player.repeatTimesLeft) more to go")
                            : String(localized: "Play this a few times"),
                        tint: player.repeatTimesLeft > 0 ? Blaze.amber : .white) {
                        showRepeatTimes = true
                    }

                    row("plus.circle", "Add to playlist") { showAddToPlaylist = true }

                    if let track = player.current, !track.videoId.isEmpty {
                        let pinned = dial.isPinned(track.videoId)
                        row(pinned ? "pin.slash" : "pin",
                            pinned ? "Unpin from speed dial" : "Pin to speed dial",
                            tint: pinned ? Blaze.amber : .white) {
                            dial.toggle(track)
                        }
                    }
                    row("quote.bubble", "Lyrics") { dismiss(); onLyrics() }
                    row("textformat.size", "Lyrics settings") { dismiss(); onLyricsSettings() }
                    row("metronome", "Lyrics timing") { dismiss(); onLyricsTiming() }
                    row("slider.horizontal.3", "Equaliser") { dismiss(); onEqualizer() }
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
        .sheet(isPresented: $showRepeatTimes) {
            RepeatTimesSheet(player: player)
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

/// How many more times round before the queue carries on.
///
/// The repeat button already has "repeat this one for ever"; this is the other
/// thing people mean by it — a song a few more times, then on with the queue.
struct RepeatTimesSheet: View {
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    private let choices = [1, 2, 3, 5, 10]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "repeat.1")
                    .font(.system(size: 22))
                    .foregroundStyle(Blaze.amber)
                Text("How many more times?")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 8)

            Text("The song plays that many more times, then the queue carries on.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ForEach(choices, id: \.self) { times in
                Button {
                    player.repeatCurrentSong(times: times)
                    dismiss()
                } label: {
                    HStack {
                        Text(times == 1 ? String(localized: "1 time")
                                        : String(localized: "\(times) times"))
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                        if player.repeatTimesLeft == times {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Blaze.amber)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if player.repeatTimesLeft > 0 {
                Button {
                    player.repeatCurrentSong(times: 0)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Stop repeating")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Blaze.surface.ignoresSafeArea())
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}
