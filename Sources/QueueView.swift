import SwiftUI

/// The play queue: every track with the now-playing row highlighted; tap to jump.
struct QueueView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(palette.accent)
                }
            }
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
