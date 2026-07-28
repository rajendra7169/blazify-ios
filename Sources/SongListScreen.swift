import SwiftUI

/// How a song list is ordered. Mirrors Android's `AutoPlaylistSongSortType`.
enum SongSort: String, CaseIterable, Identifiable {
    case createDate, name, artist, playTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createDate: "Date added"
        case .name: "Name"
        case .artist: "Artist"
        case .playTime: "Play time"
        }
    }
}

/// A capsule filter above a song list — Android's `ChipsRow`, e.g. the Songs
/// category switching between Library / Liked / Downloaded / Uploaded.
struct SongListFilter: Identifiable, Equatable {
    let id: String
    let title: String
    let tracks: [Track]

    init(_ title: String, _ tracks: [Track]) {
        id = title
        self.title = title
        self.tracks = tracks
    }
}

/// The one song-list design, ported from AutoPlaylistScreen.kt: a large centred
/// cover, the title and totals, shuffle · play · more, then a sort header and
/// the songs. Used by every list in the app so they all look the same.
struct SongListScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.playerBottomInset) private var bottomInset

    let title: String
    var filters: [SongListFilter] = []
    var tracks: [Track] = []
    @ObservedObject var player: Player

    @State private var filterIndex = 0
    @State private var sort: SongSort = .createDate
    @State private var descending = true
    @State private var searching = false
    @State private var query = ""
    @State private var showMenu = false

    /// The active filter's songs, or the plain list when there are no filters.
    private var source: [Track] {
        filters.isEmpty ? tracks : (filters[safe: filterIndex]?.tracks ?? [])
    }

    private var shown: [Track] {
        var list = source

        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
            }
        }

        switch sort {
        case .createDate: break   // already newest-first
        case .name: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist: list.sort { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .playTime: list.sort { PlayHistory.playCount($0.videoId) > PlayHistory.playCount($1.videoId) }
        }
        // `descending` means "newest / Z→A / most played first", which is how
        // the unsorted list already arrives — so flip only when it's off.
        if sort == .createDate || sort == .playTime {
            if !descending { list.reverse() }
        } else if descending {
            list.reverse()
        }
        return list
    }

    private var totalDuration: String {
        let seconds = Int(source.reduce(0) { $0 + $1.duration })
        guard seconds > 0 else { return "" }
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? " • \(h)h \(m)m" : " • \(m) min"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !filters.isEmpty { filterChips }
                header
                sortHeader

                ForEach(Array(shown.enumerated()), id: \.element.id) { index, track in
                    Button {
                        player.play(shown, startAt: index)
                        player.showFullPlayer = true
                    } label: {
                        TrackRow(track: track)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }

                if shown.isEmpty {
                    Text(query.isEmpty ? "Nothing here yet" : "No matches")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .padding(.top, 40)
                }
            }
            .padding(.bottom, 16)
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle(searching ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { searching.toggle() }
                    if !searching { query = "" }
                } label: {
                    Image(systemName: searching ? "xmark" : "magnifyingglass")
                        .foregroundStyle(palette.onSurface)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if searching { searchField }
        }
        .confirmationDialog(title, isPresented: $showMenu, titleVisibility: .visible) {
            Button("Add to queue") { player.addToQueue(source) }
            Button("Download all") { Downloads.shared.downloadAll(source) }
            Button("Export playlist") { export() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Filter capsules

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(filters.enumerated()), id: \.element.id) { index, filter in
                    let active = index == filterIndex
                    Text(filter.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? palette.onAccent : palette.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(active ? AnyShapeStyle(palette.accent)
                                           : AnyShapeStyle(palette.onSurface.opacity(0.06)))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { filterIndex = index }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    // MARK: Cover · title · transport

    private var header: some View {
        VStack(spacing: 0) {
            RemoteImage(url: source.first?.artURL(size: 720)) {
                palette.onSurface.opacity(0.06)
                    .overlay(Image(systemName: "music.note.list")
                        .font(.system(size: 56))
                        .foregroundStyle(palette.onSurface.opacity(0.35)))
            }
            .frame(width: 240, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: palette.accent.opacity(0.3), radius: 24, x: 0, y: 10)
            .padding(.top, 8)
            .padding(.bottom, 20)

            Text(title)
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 32)

            Text("\(source.count) song\(source.count == 1 ? "" : "s")\(totalDuration)")
                .font(.system(size: 14))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.top, 12)

            HStack(spacing: 16) {
                circleButton("shuffle", size: 48, filled: false) {
                    let shuffled = source.shuffled()
                    guard !shuffled.isEmpty else { return }
                    player.play(shuffled, startAt: 0)
                    player.showFullPlayer = true
                }
                circleButton("play.fill", size: 72, filled: true) {
                    guard !source.isEmpty else { return }
                    player.play(source, startAt: 0)
                    player.showFullPlayer = true
                }
                circleButton("ellipsis", size: 48, filled: false) { showMenu = true }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
    }

    private func circleButton(_ icon: String, size: CGFloat, filled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: filled ? 32 : 22, weight: filled ? .bold : .regular))
                .foregroundStyle(filled ? palette.onAccent : palette.onSurface)
                .frame(width: size, height: size)
                .background(filled ? AnyShapeStyle(palette.accent)
                                   : AnyShapeStyle(palette.surfaceHigh))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Sort

    private var sortHeader: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(SongSort.allCases) { option in
                    Button {
                        if sort == option { descending.toggle() } else { sort = option }
                    } label: {
                        Label(option.title, systemImage: sort == option
                              ? (descending ? "arrow.down" : "arrow.up") : "")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sort.title)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: descending ? "arrow.down" : "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(palette.accent)
            }
            Spacer()
            Text("\(shown.count)")
                .font(.system(size: 13))
                .foregroundStyle(palette.onSurfaceVariant)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.onSurfaceVariant)
            TextField("Search in \(title)", text: $query)
                .foregroundStyle(palette.onSurface)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.surfaceHigh)
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(palette.scaffold)
    }

    /// Writes the list out as M3U so it can be shared or re-imported.
    private func export() {
        var text = "#EXTM3U\n"
        for track in source {
            text += "#EXTINF:\(Int(track.duration)),\(track.artist) - \(track.title)\n"
            text += "https://music.youtube.com/watch?v=\(track.videoId)\n"
        }
        let name = title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).m3u")
        try? text.write(to: url, atomically: true, encoding: .utf8)

        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController?
            .present(share, animated: true)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
