import Foundation

/// What you keep to hand: songs, playlists and artists pinned to the top of Home.
///
/// The recommendations underneath change every time the feed loads, which is what
/// makes them worth reading — and exactly why the two or three things somebody
/// reaches for every day need somewhere that does not move. That is this.
@MainActor
final class SpeedDial: ObservableObject {
    static let shared = SpeedDial()

    enum Kind: String, Codable {
        case song, playlist, artist
    }

    struct Pin: Codable, Identifiable, Hashable {
        /// The video id for a song, the browse id for anything else.
        let key: String
        let kind: Kind
        let title: String
        let subtitle: String
        let thumbnail: String
        /// A song carries what it takes to play it without asking anybody first.
        var duration: Double = 0
        var artistId: String?
        var pinnedAt = Date()

        var id: String { key }

        var track: Track {
            Track(videoId: key, title: title, artist: subtitle, thumbnail: thumbnail,
                  duration: duration, artistId: artistId)
        }

        /// The row a playlist or an artist opens from, rebuilt from what was kept.
        var item: HomeItem {
            HomeItem(title: title, subtitle: subtitle, thumbnail: thumbnail,
                     videoId: kind == .song ? key : nil,
                     browseId: kind == .song ? nil : key,
                     isCircular: kind == .artist)
        }
    }

    /// Oldest first, so pinning something new never shuffles the tile somebody
    /// was reaching for.
    @Published private(set) var pins: [Pin] = []

    /// A screenful. Past this the oldest gives way, because a speed dial that
    /// scrolls for a minute is just another list.
    static let limit = 24

    private let store = "speedDial"

    private init() {
        guard let data = UserDefaults.standard.data(forKey: store),
              let saved = try? JSONDecoder().decode([Pin].self, from: data)
        else { return }
        pins = saved
    }

    func isPinned(_ key: String) -> Bool { pins.contains { $0.key == key } }

    var songs: [Track] { pins.filter { $0.kind == .song }.map(\.track) }

    var isEmpty: Bool { pins.isEmpty }

    func pin(_ track: Track) {
        guard !track.videoId.isEmpty else { return }
        add(Pin(key: track.videoId, kind: .song, title: track.title,
                subtitle: track.artist, thumbnail: track.thumbnail,
                duration: track.duration, artistId: track.artistId))
    }

    /// A playlist, album or artist from a feed row.
    func pin(_ item: HomeItem) {
        if let videoId = item.videoId, !videoId.isEmpty, item.browseId == nil {
            pin(item.asTrack)
            return
        }
        guard let browseId = item.browseId, !browseId.isEmpty else { return }
        add(Pin(key: browseId, kind: item.isCircular ? .artist : .playlist,
                title: item.title, subtitle: item.subtitle, thumbnail: item.thumbnail))
    }

    func unpin(_ key: String) {
        pins.removeAll { $0.key == key }
        save()
    }

    func toggle(_ track: Track) {
        isPinned(track.videoId) ? unpin(track.videoId) : pin(track)
    }

    func toggle(_ item: HomeItem) {
        let key = item.browseId ?? item.videoId ?? ""
        isPinned(key) ? unpin(key) : pin(item)
    }

    private func add(_ pin: Pin) {
        guard !isPinned(pin.key) else { return }
        pins.append(pin)
        if pins.count > Self.limit { pins.removeFirst(pins.count - Self.limit) }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pins) else { return }
        UserDefaults.standard.set(data, forKey: store)
    }
}
