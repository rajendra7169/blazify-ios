import Foundation

/// Where a song that plays without a connection is kept.
enum OfflineSource: Hashable {
    /// Kept whole in the song cache after being played.
    case cached
    /// Downloaded on purpose.
    case downloaded
    /// One of the listener's own files on the phone.
    case device
}

/// A song that plays without a connection, and where it is kept.
struct SavedSong {
    let track: Track
    let sources: Set<OfflineSource>
}

/// Every song that plays without a connection: downloaded, kept whole in the
/// song cache, or one of the listener's own files, each with where it is kept.
/// Read when asked rather than kept up to date, since most days nobody asks;
/// all three lists are already in memory, so asking is cheap.
enum OfflineSongs {
    static func all() -> [SavedSong] {
        var order: [String] = []
        var tracks: [String: Track] = [:]
        var sources: [String: Set<OfflineSource>] = [:]
        func add(_ list: [Track], _ source: OfflineSource) {
            for track in list where !track.videoId.isEmpty {
                if tracks[track.videoId] == nil {
                    order.append(track.videoId)
                    tracks[track.videoId] = track
                }
                sources[track.videoId, default: []].insert(source)
            }
        }
        add(Downloads.shared.tracks, .downloaded)
        add(AudioCache.shared.tracks, .cached)
        add(LocalMusic.shared.tracks, .device)
        return order.compactMap { id in
            tracks[id].map { SavedSong(track: $0, sources: sources[id] ?? []) }
        }
    }

    /// The saved songs that match what was typed, by title and artist (a song
    /// here carries no album), accents and capitals aside, best first. The
    /// content filters apply as they do everywhere else.
    static func search(_ query: String) -> [Track] {
        let songs = ContentPrefs.filtered(all().map(\.track))
        return OfflineSearch.search(query, in: songs, title: \.title, others: { [$0.artist] })
    }
}
