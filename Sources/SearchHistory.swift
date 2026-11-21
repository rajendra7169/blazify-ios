import Foundation
import Combine

/// Recently searched queries, our own store of the
/// table. Newest first, de-duplicated, capped so the chip row stays sensible.
final class SearchHistory: ObservableObject {
    static let shared = SearchHistory()

    private let key = "searchHistory"
    private let limit = 30

    @Published private(set) var queries: [String] = []

    private init() {
        // Twins saved before searches were kept once whatever their capitals
        // are hidden: the newest of each stays.
        var seen = Set<String>()
        queries = (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { seen.insert(Self.sameness($0)).inserted }
    }

    /// What two searches have to share to be the same search: "the weeknd"
    /// and "The Weeknd " are one.
    private static func sameness(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func add(_ query: String) {
        // Privacy > Pause search history.
        guard !UserDefaults.standard.bool(forKey: "pauseSearchHistory") else { return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        // Once, whatever its capitals: written the newer way, moved to the top.
        let same = Self.sameness(q)
        queries.removeAll { Self.sameness($0) == same }
        queries.insert(q, at: 0)
        if queries.count > limit { queries = Array(queries.prefix(limit)) }
        save()
    }

    /// Removing a search removes its twins written with other capitals too.
    func remove(_ query: String) {
        let same = Self.sameness(query)
        queries.removeAll { Self.sameness($0) == same }
        save()
    }

    func clear() {
        queries = []
        save()
    }

 /// History entries that match what's been typed so far, as we show
    /// above the live suggestions.
    func matching(_ query: String, limit: Int = 3) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return queries.filter { $0.lowercased().contains(q) && Self.sameness($0) != q }
            .prefix(limit).map { $0 }
    }

    private func save() {
        UserDefaults.standard.set(queries, forKey: key)
    }
}
