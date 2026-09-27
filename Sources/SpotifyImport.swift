import Foundation

/// How far a result's length may differ from Spotify's before it is somebody
/// else's song. At file scope because the matching runs off the main actor.
private let toleranceSeconds = 8.0

/// Searches in flight at once: enough to be quick, few enough to stay polite.
private let atOnce = 4

/// Rebuilds a Spotify playlist here.
///
/// Spotify's tracks are names, not addresses: nothing in one library points at
/// anything in the other. So each one is searched for by title and artist and
/// accepted only when the length agrees too — the wrong song under the right
/// name is worse than an honest gap, and a gap is reported rather than hidden.
@MainActor
enum SpotifyImport {
    struct Outcome {
        let name: String
        /// The new playlist on the account, or nil when it could not be created.
        let playlistId: String?
        /// The songs that were found, in the order Spotify lists them.
        let songs: [Track]
        let total: Int
        /// Titles nothing was found for, in the order they appear on Spotify.
        let missing: [String]
        let mayHaveMore: Bool

        var matched: Int { songs.count }
    }

    enum Failure: LocalizedError {
        case notSignedIn
        case playlistNotCreated

        var errorDescription: String? {
            switch self {
            case .notSignedIn: String(localized: "Sign in to import a playlist.")
            case .playlistNotCreated: String(localized: "Could not create the playlist.")
            }
        }
    }

    /// Reads the link, finds each song here, and keeps them as a new playlist on
    /// the account. `onProgress` is called as each search finishes.
    static func run(
        link: String,
        onProgress: (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> Outcome {
        guard Auth.shared.isLoggedIn else { throw Failure.notSignedIn }

        let playlist = try await SpotifyPlaylist.read(link)
        let found = try await search(playlist.tracks, onProgress: onProgress)

        guard let playlistId = await YouTube.createPlaylist(title: playlist.name) else {
            throw Failure.playlistNotCreated
        }
        let songs = found.compactMap { $0 }
        _ = await YouTube.addToPlaylist(playlistId: playlistId, videoIds: songs.map(\.videoId))

        let missing = zip(playlist.tracks, found).compactMap { track, match in
            match == nil ? track.title : nil
        }
        return Outcome(
            name: playlist.name,
            playlistId: playlistId,
            songs: songs,
            total: playlist.tracks.count,
            missing: missing,
            mayHaveMore: playlist.mayHaveMore)
    }

    /// One slot per Spotify track, holding what was found for it or nil.
    ///
    /// Only `atOnce` searches run at a time: a hundred at once is a hundred
    /// requests in one breath, which is how a client starts being refused.
    private static func search(
        _ tracks: [SpotifyPlaylist.Track],
        onProgress: (_ done: Int, _ total: Int) -> Void
    ) async throws -> [Track?] {
        var found = [Track?](repeating: nil, count: tracks.count)
        var done = 0
        onProgress(0, tracks.count)

        await withTaskGroup(of: (Int, Track?).self) { group in
            var next = 0
            while next < min(atOnce, tracks.count) {
                let index = next, track = tracks[next]
                group.addTask {
                    let song = await Self.match(track)
                    return (index, song)
                }
                next += 1
            }
            while let (index, match) = await group.next() {
                found[index] = match
                done += 1
                onProgress(done, tracks.count)
                // One in, one out: the next search starts only as a slot frees up.
                if next < tracks.count {
                    let index = next, track = tracks[next]
                    group.addTask {
                        let song = await Self.match(track)
                        return (index, song)
                    }
                    next += 1
                }
            }
        }
        try Task.checkCancellation()
        return found
    }

    nonisolated private static func match(_ track: SpotifyPlaylist.Track) async -> Track? {
        let query = [track.title, track.artists]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
        let results = await YouTube.search(query, scope: .songs)
        return pick(from: results, for: track)
    }

    /// The closest result by length, or nothing.
    ///
    /// A track Spotify has no length for (it happens) is matched on names alone,
    /// since there is nothing to compare.
    nonisolated static func pick(from results: [Track], for track: SpotifyPlaylist.Track) -> Track? {
        guard !results.isEmpty else { return nil }
        guard track.durationSeconds > 0 else { return results.first }
        let wanted = Double(track.durationSeconds)
        return results
            .filter { $0.duration > 0 }
            .map { ($0, abs($0.duration - wanted)) }
            .filter { $0.1 <= toleranceSeconds }
            .min { $0.1 < $1.1 }?
            .0
    }
}
