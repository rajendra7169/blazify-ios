import SwiftUI

/// A playlist or album opened from a home card: big art header, Play / Shuffle
/// actions, then the track list. Tapping any row starts playback from there.
struct PlaylistView: View {
    @Environment(\.palette) private var palette
    let item: HomeItem
    @ObservedObject var player: Player
    @ObservedObject private var downloads = Downloads.shared
    /// Whether this one is in the user's library, as far as this phone knows.
    @State private var saved = false
    @ObservedObject private var dial = SpeedDial.shared

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
        ScrollViewReader { scroller in
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
                    actionRow
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
                                .swipeActions(edge: .leading) {
                                    Button { player.playNext(track) } label: {
                                        Label("Play next",
                                              systemImage: "text.line.first.and.arrowtriangle.forward")
                                    }
                                    .tint(Blaze.amber)
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
                            }
                            .id(pair.element.videoId)
                            .padding(.leading, 16)
                            .padding(.vertical, 6)
                            .buttonStyle(.plain)
                            // Swipe it right and it comes up next.
                            .swipeToPlayNext(pair.element, player: player)
                        }
                    }
                }
            }
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
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
        .task {
            saved = SavedPlaylists.contains(item.browseId ?? "")
            await load()
        }
        // Opens on the playing song once the songs are in, when it is one of
        // them. A moment's wait: a lazy list scrolled before it has laid
        // itself out lands somewhere near, not on, the row.
        .onChange(of: loading) {
            guard !loading, let id = player.current?.videoId, tracks.contains(where: { $0.videoId == id }) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scroller.scrollTo(id, anchor: .center)
            }
        }
        }
    }

    /// Save and download on the left, Play in the middle, shuffle and more on
    /// the right — the Android app's row. Always five places, so Play stays in
    /// the middle whatever the page offers.
    private var actionRow: some View {
        HStack {
            if auth.isLoggedIn, let id = item.browseId, !id.isEmpty {
                roundButton(saved ? "heart.fill" : "heart",
                            tint: saved ? Color(hex: 0xFF5A5F) : nil) { toggleSaved(id) }
            } else {
                Color.clear.frame(width: 46, height: 46)
            }
            Spacer()
            downloadButton
            Spacer()
            Button {
                // Settings → Player → Shuffle playlists on open.
                let order = PlaybackPrefs.shared.shufflePlaylistFirst ? tracks.shuffled() : tracks
                player.play(order, startAt: 0)
                player.openFullPlayer()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(palette.heroGradient)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play")
            Spacer()
            roundButton("shuffle") {
                player.play(tracks.shuffled(), startAt: 0)
                player.openFullPlayer()
            }
            Spacer()
            if isEditable || !(item.browseId ?? "").isEmpty {
                editMenu
            } else {
                Color.clear.frame(width: 46, height: 46)
            }
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 20)
    }

    @ViewBuilder private var downloadButton: some View {
        let states = tracks.map { downloads.state($0.videoId) }
        if states.allSatisfy({ $0 == .done }) {
            roundButton("checkmark.circle.fill", tint: palette.accent) {}
                .disabled(true)
                .accessibilityLabel("Downloaded")
        } else if states.contains(.downloading) {
            BlazeLoader(size: 30)
                .frame(width: 46, height: 46)
                .background(palette.onSurface.opacity(0.10))
                .clipShape(Circle())
        } else {
            roundButton("arrow.down") { Downloads.shared.downloadAll(tracks) }
                .accessibilityLabel(downloadLabel)
        }
    }

    private func roundButton(_ icon: String, tint: Color? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint ?? palette.onSurface)
                .frame(width: 46, height: 46)
                .background(palette.onSurface.opacity(0.10))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func toggleSaved(_ id: String) {
        let next = !saved
        saved = next
        SavedPlaylists.set(id, next)
        Task {
            if await !YouTube.ratePlaylist(browseId: id, like: next) {
                await MainActor.run {
                    saved = !next
                    SavedPlaylists.set(id, !next)
                    notice = "Couldn't update your library. Try again in a moment."
                }
            }
        }
    }

    /// The ⋮ menu: pinning it, for any playlist, and the editing items for one of
    /// your own.
    @ViewBuilder private var editMenu: some View {
        if isEditable || !(item.browseId ?? "").isEmpty {
            Menu {
                if let browseId = item.browseId, !browseId.isEmpty {
                    Button { dial.toggle(item) } label: {
                        Label(dial.isPinned(browseId)
                              ? "Unpin from speed dial" : "Pin to speed dial",
                              systemImage: dial.isPinned(browseId) ? "pin.slash" : "pin")
                    }
                }
                if isEditable {
                    Divider()
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
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .frame(width: 46, height: 46)
                    .background(palette.onSurface.opacity(0.10))
                    .clipShape(Circle())
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


/// The playlists and albums saved to the library from this phone, so the heart
/// shows filled when one is opened again. YouTube does not say which are saved
/// without a request per page; this remembers the answer it was given.
enum SavedPlaylists {
    private static let key = "savedPlaylistIds"

    static func contains(_ id: String) -> Bool {
        !id.isEmpty && (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id)
    }

    static func set(_ id: String, _ saved: Bool) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if saved { ids.insert(id) } else { ids.remove(id) }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}
