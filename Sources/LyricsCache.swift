import Foundation

/// Lyrics fetched ahead of time, so opening the lyrics pane is instant.
///
/// The player warms this as soon as a song starts and again for whatever is
/// queued next, which is why lyrics no longer appear only after you tap through
/// and wait for five providers to answer.
actor LyricsCache {
    static let shared = LyricsCache()

    private var store: [String: [LyricsCandidate]] = [:]
    private var inFlight: Set<String> = []
    /// Plenty for a listening session; keeps memory trivial.
    private let limit = 40
    private var order: [String] = []

    /// Cached candidates for a song, if we already fetched them.
    func candidates(for videoId: String) -> [LyricsCandidate]? {
        store[videoId]
    }

    /// Fetch and cache unless it's already cached or being fetched.
    @discardableResult
    func warm(videoId: String, title: String, artist: String,
              duration: Double) async -> [LyricsCandidate] {
        if let hit = store[videoId] { return hit }
        guard !inFlight.contains(videoId), !videoId.isEmpty else { return [] }
        inFlight.insert(videoId)
        defer { inFlight.remove(videoId) }

        let found = await Lyrics.search(title: title, artist: artist,
                                        videoId: videoId, duration: duration)
        guard !found.isEmpty else { return [] }

        store[videoId] = found
        order.removeAll { $0 == videoId }
        order.append(videoId)
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            store[oldest] = nil
        }
        return found
    }

    func clear() {
        store = [:]
        order = []
    }
}
