import SwiftUI

/// The play queue: every track with the now-playing row highlighted; tap to jump.
struct QueueView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = Auth.shared

    @State private var showSave = false
    @State private var playlistName = ""
    @State private var saving = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { pair in
                    let active = pair.offset == player.index
                    HStack(spacing: 0) {
                        Button {
                            player.jump(to: pair.offset)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                            RemoteImage(url: pair.element.thumbnailURL, size: 48) {
                                palette.onSurface.opacity(0.10)
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.element.title)
                                    .font(.subheadline)
                                    .foregroundStyle(active ? palette.accent : palette.onSurface)
                                    .lineLimit(1)
                                Text(pair.element.artist)
                                    .font(.caption)
                                    .foregroundStyle(palette.onSurfaceVariant)
                                    .lineLimit(1)
                            }
                                Spacer(minLength: 0)
                                if active {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.caption)
                                        .foregroundStyle(palette.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        QueueRowMenu(track: pair.element, player: player,
                                     position: pair.offset)
                    }
                    .listRowBackground(active ? palette.onSurface.opacity(0.08) : Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            player.removeFromQueue(at: pair.offset)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .onMove { from, to in player.moveInQueue(from: from, to: to) }
            }
            .environment(\.editMode, .constant(.active))
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Only offered when there's an account to save it to — a
                // playlist is created server-side, not on the phone.
                if auth.isLoggedIn, !player.queue.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { playlistName = ""; showSave = true } label: {
                            if saving {
                                ProgressView().tint(palette.accent)
                            } else {
                                Image(systemName: "text.badge.plus")
                            }
                        }
                        .tint(palette.accent)
                        .disabled(saving)
                        .accessibilityLabel("Save queue as a playlist")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(palette.accent)
                }
            }
            .overlay(alignment: .bottom) {
                if let notice {
                    Text(notice)
                        .font(.blaze(13, .semibold))
                        .foregroundStyle(palette.onSurface)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(palette.surfaceHigh)
                        .clipShape(Capsule())
                        .padding(.bottom, 28)
                        .transition(.opacity)
                }
            }
            .alert("Save queue as a playlist", isPresented: $showSave) {
                TextField("Name", text: $playlistName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { save() }
            } message: {
                Text("Creates a new playlist on your account with everything in the queue.")
            }
        }
    }

    /// Songs on this phone have no video id on YouTube, so they can't go into a
    /// playlist that lives on the account — everything else does.
    private func save() {
        let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = player.queue.map(\.videoId).filter { !LocalMusic.isLocal($0) }
        guard !name.isEmpty, !ids.isEmpty else { return }
        saving = true
        Task {
            var added = 0
            if let playlistId = await YouTube.createPlaylist(title: name) {
                // One at a time: the batch endpoint rejects long lists, and a
                // half-created playlist is worse than a slow one.
                for videoId in ids {
                    if await YouTube.addToPlaylist(playlistId: playlistId, videoId: videoId) {
                        added += 1
                    }
                }
            }
            let done = added
            await MainActor.run {
                saving = false
                show(done == 0 ? String(localized: "Couldn't save the playlist")
                               : String(localized: "Saved \(done) songs to \(name)"))
            }
        }
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation { notice = nil }
        }
    }
}


/// The queue row's ⋮: the shared song actions plus the two that only make sense
/// here — play it next, or take it out.
private struct QueueRowMenu: View {
    @Environment(\.palette) private var palette
    let track: Track
    @ObservedObject var player: Player
    let position: Int

    @State private var playlistTrack: Track?

    var body: some View {
        Menu {
            Button {
                player.removeFromQueue(at: position)
                player.playNext(track)
            } label: {
                Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                player.setFavorite(track, liked: !player.favorites.contains(track.videoId))
            } label: {
                Label(player.favorites.contains(track.videoId)
                      ? "Remove from favourites" : "Add to favourites",
                      systemImage: player.favorites.contains(track.videoId) ? "heart.slash" : "heart")
            }
            Button { playlistTrack = track } label: {
                Label("Add to playlist", systemImage: "plus.circle")
            }
            Button { Downloads.shared.download(track) } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            Divider()
            Button(role: .destructive) {
                player.removeFromQueue(at: position)
            } label: {
                Label("Remove from queue", systemImage: "minus.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.blaze(15))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .sheet(item: $playlistTrack) { AddToPlaylistSheet(track: $0) }
    }
}
