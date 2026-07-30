import SwiftUI

/// A playlist or album opened from a home card: big art header, Play / Shuffle
/// actions, then the track list. Tapping any row starts playback from there.
struct PlaylistView: View {
    @Environment(\.palette) private var palette
    let item: HomeItem
    @ObservedObject var player: Player
    @ObservedObject private var downloads = Downloads.shared

    @ObservedObject private var auth = Auth.shared
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var editing = false
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false
    @State private var notice: String?
    @Environment(\.dismiss) private var dismiss

    /// Only your own playlists can be edited — an album or someone else's
    /// playlist has no edit endpoint, so the controls stay hidden.
    private var isEditable: Bool {
        guard auth.isLoggedIn, !tracks.isEmpty, let id = item.browseId else { return false }
        // Albums can't be edited. Everything else is judged on capability
        // rather than on the id's shape: a row YouTube will let us move or
        // remove carries a setVideoId, and that's the only reliable signal —
        // a "VL" prefix check missed playlists opened from some screens.
        guard !id.hasPrefix("MPREb"), !id.contains("OLAK5uy") else { return false }
        return tracks.contains { $0.setVideoId != nil }
    }

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
                RemoteImage(url: item.thumbnailURL, size: 220) {
                    palette.onSurface.opacity(0.06)
                        .overlay(Image(systemName: "music.note.list")
                            .font(.blaze(48))
                            .foregroundStyle(palette.onSurface.opacity(0.35)))
                }
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 12)
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text(item.title)
                        .font(.blaze(22, .bold))
                        .foregroundStyle(palette.onSurface)
                        .multilineTextAlignment(.center)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.blaze(14))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                if !tracks.isEmpty {
                    HStack(spacing: 10) {
                        actionButton("Play", "play.fill") {
                            // Settings → Player → Shuffle playlists on open.
                            let order = PlaybackPrefs.shared.shufflePlaylistFirst
                                ? tracks.shuffled() : tracks
                            player.play(order, startAt: 0)
                            player.showFullPlayer = true
                        }
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
                } else if editing {
                    // A List is the only thing that gives drag handles and
                    // swipe-to-delete, so editing swaps to one.
                    List {
                        ForEach(tracks) { track in
                            TrackRow(track: track)
                                .listRowBackground(palette.scaffold)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { remove(track) } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                        .onMove { from, to in move(from: from, to: to) }
                    }
                    .environment(\.editMode, .constant(.active))
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: CGFloat(tracks.count) * 68)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { pair in
                            SongRow(track: pair.element, player: player) {
                                player.play(tracks, startAt: pair.offset)
                                player.showFullPlayer = true
                            }
                            .padding(.leading, 16)
                            .padding(.vertical, 6)
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { editMenu }
        }
        .alert("Rename playlist", isPresented: $renaming) {
            TextField("Name", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") { rename() }
        }
        .alert("Delete this playlist?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deletePlaylist() }
        } message: {
            Text("It will be removed from your YouTube Music account too.")
        }
        .alert("Couldn't do that",
               isPresented: Binding(get: { notice != nil },
                                    set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
        .task { await load() }
    }

    private func actionButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.blaze(15, .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(palette.heroGradient)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// The edit menu, shown only for playlists you own.
    @ViewBuilder private var editMenu: some View {
        if isEditable {
            Menu {
                Button {
                    withAnimation { editing.toggle() }
                } label: {
                    Label(editing ? "Done" : "Reorder or remove",
                          systemImage: editing ? "checkmark" : "arrow.up.arrow.down")
                }
                Button {
                    newTitle = item.title
                    renaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete playlist", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.blaze(17, .semibold))
                    .foregroundStyle(palette.accent)
            }
        }
    }

    private func remove(_ track: Track) {
        guard let playlistId = item.browseId, let setId = track.setVideoId else {
            notice = "This row can't be removed."
            return
        }
        let previous = tracks
        withAnimation { tracks.removeAll { $0.setVideoId == setId } }
        Task {
            let ok = await YouTube.removeFromPlaylist(playlistId: playlistId,
                                                      videoId: track.videoId,
                                                      setVideoId: setId)
            if !ok {
                // Put it back rather than leaving the screen disagreeing with
                // the account.
                await MainActor.run {
                    tracks = previous
                    notice = "Couldn't remove that song."
                }
            }
        }
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        guard let playlistId = item.browseId,
              let source = offsets.first,
              tracks.indices.contains(source) else { return }
        let moved = tracks[source]
        guard let setId = moved.setVideoId else {
            notice = "This row can't be moved."
            return
        }
        let previous = tracks
        withAnimation { tracks.move(fromOffsets: offsets, toOffset: destination) }

        // YouTube positions a row AFTER another row, so send the new neighbour.
        let landed = tracks.firstIndex { $0.setVideoId == setId }
        let predecessor = landed.flatMap { $0 > 0 ? tracks[$0 - 1].setVideoId : nil }
        Task {
            let ok = await YouTube.moveInPlaylist(playlistId: playlistId,
                                                  setVideoId: setId,
                                                  afterSetVideoId: predecessor)
            if !ok {
                await MainActor.run {
                    tracks = previous
                    notice = "Couldn't reorder that song."
                }
            }
        }
    }

    private func rename() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard let playlistId = item.browseId, !title.isEmpty else { return }
        Task {
            let ok = await YouTube.renamePlaylist(playlistId: playlistId, title: title)
            if !ok { await MainActor.run { notice = "Couldn't rename the playlist." } }
        }
    }

    private func deletePlaylist() {
        guard let playlistId = item.browseId else { return }
        Task {
            let ok = await YouTube.deletePlaylist(playlistId: playlistId)
            await MainActor.run {
                if ok { dismiss() } else { notice = "Couldn't delete the playlist." }
            }
        }
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
