import Foundation

/// One play, stamped with when it happened — the equivalent of Android's
/// `Event` row. Stats and the History screen both need the timestamp, which the
/// old "ordered list of tracks" store couldn't give us.
struct PlayEvent: Codable, Hashable {
    let videoId: String
    let at: Date
}

/// How far back a Stats view reaches. Mirrors Android's `StatPeriod`.
enum StatPeriod: String, CaseIterable, Identifiable {
    case week1, month1, month3, month6, year1, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week1: "1 week"
        case .month1: "1 month"
        case .month3: "3 months"
        case .month6: "6 months"
        case .year1: "1 year"
        case .all: "All time"
        }
    }

    /// The earliest instant this period includes.
    var since: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .week1: return cal.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .month1: return cal.date(byAdding: .month, value: -1, to: now) ?? now
        case .month3: return cal.date(byAdding: .month, value: -3, to: now) ?? now
        case .month6: return cal.date(byAdding: .month, value: -6, to: now) ?? now
        case .year1: return cal.date(byAdding: .year, value: -1, to: now) ?? now
        case .all: return .distantPast
        }
    }
}

/// The bucket a play falls into on the History screen. Mirrors Android's
/// `DateAgo`, including its "this week starts on Monday" rule.
enum DateAgo: Hashable {
    case today, yesterday, thisWeek, lastWeek
    case other(Date)   // first of that month

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .lastWeek: "Last week"
        case .other(let date):
            let f = DateFormatter()
            f.dateFormat = "yyyy/MM"
            return f.string(from: date)
        }
    }

    /// Sort key: newest bucket first, exactly as Android orders them.
    var order: Int {
        switch self {
        case .today: 0
        case .yesterday: 1
        case .thisWeek: 2
        case .lastWeek: 3
        case .other(let date): 4 + max(0, Calendar.current.dateComponents(
            [.day], from: date, to: Date()).day ?? 0)
        }
    }

    static func of(_ date: Date) -> DateAgo {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let today = cal.startOfDay(for: Date())
        let daysAgo = cal.dateComponents([.day], from: day, to: today).day ?? 0

        if daysAgo == 0 { return .today }
        if daysAgo == 1 { return .yesterday }

        // Weeks run Monday-to-Monday, matching Android.
        var monday = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        monday.weekday = 2
        let thisMonday = cal.date(from: monday) ?? today
        let lastMonday = cal.date(byAdding: .weekOfYear, value: -1, to: thisMonday) ?? today

        if day >= thisMonday { return .thisWeek }
        if day >= lastMonday { return .lastWeek }

        let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: day)) ?? day
        return .other(firstOfMonth)
    }
}

/// Local listening history: an append-only event log plus the tracks it refers
/// to, so we can answer "what did I play, and when".
enum PlayHistory {
    private static let eventsKey = "playEvents"
    private static let tracksKey = "playedTracks"
    private static let limit = 3000

    // MARK: Recording

    static func record(_ track: Track) {
        guard !track.videoId.isEmpty else { return }
        var events = self.events
        events.append(PlayEvent(videoId: track.videoId, at: Date()))
        if events.count > limit { events.removeFirst(events.count - limit) }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: eventsKey)
        }

        var known = tracks
        known.removeAll { $0.videoId == track.videoId }
        known.insert(track, at: 0)
        if known.count > 500 { known = Array(known.prefix(500)) }
        if let data = try? JSONEncoder().encode(known) {
            UserDefaults.standard.set(data, forKey: tracksKey)
        }
    }

    // MARK: Reading

    static var events: [PlayEvent] {
        guard let data = UserDefaults.standard.data(forKey: eventsKey),
              let list = try? JSONDecoder().decode([PlayEvent].self, from: data) else { return [] }
        return list
    }

    /// Every track we've ever played, newest first.
    static var tracks: [Track] {
        guard let data = UserDefaults.standard.data(forKey: tracksKey),
              let list = try? JSONDecoder().decode([Track].self, from: data) else { return [] }
        return list
    }

    private static var byId: [String: Track] {
        Dictionary(tracks.map { ($0.videoId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Distinct songs, most recently played first.
    static var recent: [Track] {
        let lookup = byId
        var seen = Set<String>()
        var out: [Track] = []
        for event in events.reversed() where !seen.contains(event.videoId) {
            seen.insert(event.videoId)
            if let track = lookup[event.videoId] { out.append(track) }
        }
        // Anything played before the event log existed still belongs here.
        for track in tracks where !seen.contains(track.videoId) {
            seen.insert(track.videoId)
            out.append(track)
        }
        return out
    }

    /// Most-played songs within a period — what Android's Trending rail and the
    /// Stats screen both show.
    static func mostPlayed(_ period: StatPeriod = .all, limit: Int = 50) -> [Track] {
        let since = period.since
        var counts: [String: Int] = [:]
        for event in events where event.at >= since {
            counts[event.videoId, default: 0] += 1
        }
        // Fall back to legacy counters so existing installs aren't suddenly empty.
        if counts.isEmpty, period == .all {
            counts = UserDefaults.standard.dictionary(forKey: "playCounts") as? [String: Int] ?? [:]
        }
        let lookup = byId
        return counts.sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { lookup[$0.key] }
    }

    /// Play count for one song within a period, for the Stats list.
    static func playCount(_ videoId: String, in period: StatPeriod = .all) -> Int {
        let since = period.since
        return events.filter { $0.videoId == videoId && $0.at >= since }.count
    }

    /// The most-played artists in a period, derived from the songs' credits.
    static func topArtists(_ period: StatPeriod = .all, limit: Int = 20) -> [(name: String, plays: Int)] {
        let since = period.since
        let lookup = byId
        var counts: [String: Int] = [:]
        for event in events where event.at >= since {
            guard let artist = lookup[event.videoId]?.artist, !artist.isEmpty else { continue }
            for name in artist.split(separator: ",").map({
                $0.trimmingCharacters(in: .whitespaces)
            }) where !name.isEmpty {
                counts[name, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (name: $0.key, plays: $0.value) }
    }

    /// History grouped into Today / Yesterday / This week / … , newest first.
    static var grouped: [(bucket: DateAgo, tracks: [Track])] {
        let lookup = byId
        var buckets: [DateAgo: [Track]] = [:]
        var seen: Set<String> = []

        for event in events.reversed() {
            // One entry per song per bucket, as Android's distinct list does.
            let bucket = DateAgo.of(event.at)
            let key = "\(bucket.order)_\(event.videoId)"
            guard !seen.contains(key), let track = lookup[event.videoId] else { continue }
            seen.insert(key)
            buckets[bucket, default: []].append(track)
        }
        return buckets
            .map { (bucket: $0.key, tracks: $0.value) }
            .sorted { $0.bucket.order < $1.bucket.order }
    }

    /// Top songs of all time, kept for the Library banner.
    static var top: [Track] { mostPlayed(.all, limit: 50) }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: eventsKey)
        UserDefaults.standard.removeObject(forKey: tracksKey)
        UserDefaults.standard.removeObject(forKey: "playCounts")
    }
}
