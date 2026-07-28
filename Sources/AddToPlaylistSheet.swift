import SwiftUI

/// "Add to playlist", ported from AddToPlaylistDialog.kt: a Create playlist
/// action on top, then the user's editable playlists. Creating one adds the
/// song to it straight away.
struct AddToPlaylistSheet: View {
    @Environment(\.palette) private var palette
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = Auth.shared

    @State private var playlists: [UserPlaylist] = []
    @State private var loading = true
    @State private var busyID: String?
    @State private var addedID: String?
    @State private var creating = false
    @State private var newName = ""
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isLoggedIn {
                    message("Sign in to use playlists", icon: "person.crop.circle.badge.xmark")
                } else if loading {
                    ScrollView { SkeletonTrackList(rows: 5).padding(.top, 12) }
                } else {
                    List {
                        Button { creating = true } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "plus")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .frame(width: 44, height: 44)
                                    .background(palette.accent)
                                    .clipShape(Circle())
                                Text("Create playlist")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(palette.onSurface)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)

                        ForEach(playlists) { playlist in
                            Button { add(to: playlist) } label: { row(playlist) }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .disabled(busyID != nil)
                        }

                        if playlists.isEmpty {
                            Text("No playlists yet")
                                .foregroundStyle(palette.onSurfaceVariant)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(palette.surface.ignoresSafeArea())
            .navigationTitle("Add to playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(palette.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
        .alert("New playlist", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Create") { create() }
        }
        .alert("Couldn't update the playlist", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func row(_ playlist: UserPlaylist) -> some View {
        HStack(spacing: 14) {
            RemoteImage(url: playlist.thumbnailURL, size: 56) {
                palette.onSurface.opacity(0.06)
                    .overlay(Image(systemName: "music.note.list")
                        .foregroundStyle(palette.onSurface.opacity(0.35)))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(playlist.title)
                .font(.system(size: 16))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
            Spacer(minLength: 0)

            if busyID == playlist.id {
                ProgressView().tint(palette.onSurface)
            } else if addedID == playlist.id {
                Image(systemName: "checkmark").foregroundStyle(palette.accent)
            }
        }
        .contentShape(Rectangle())
    }

    private func message(_ text: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(palette.accent)
            Text(text).foregroundStyle(palette.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func add(to playlist: UserPlaylist) {
        busyID = playlist.id
        Task {
            let ok = await YouTube.addToPlaylist(playlistId: playlist.id, videoId: track.videoId)
            await MainActor.run {
                busyID = nil
                if ok {
                    addedID = playlist.id
                } else {
                    failed = true
                }
            }
            if ok {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await MainActor.run { dismiss() }
            }
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        newName = ""
        guard !name.isEmpty else { return }
        Task {
            guard let id = await YouTube.createPlaylist(title: name) else {
                await MainActor.run { failed = true }
                return
            }
            let ok = await YouTube.addToPlaylist(playlistId: id, videoId: track.videoId)
            await MainActor.run {
                if ok { dismiss() } else { failed = true }
            }
        }
    }

    private func load() async {
        loading = true
        let p = await YouTube.editablePlaylists()
        await MainActor.run {
            playlists = p
            loading = false
        }
    }
}
