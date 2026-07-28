import Foundation
import Combine

/// Recently searched queries, the equivalent of Android's `search_history`
/// table. Newest first, de-duplicated, capped so the chip row stays sensible.
final class SearchHistory: ObservableObject {
    static let shared = SearchHistory()

    private let key = "searchHistory"
    private let limit = 30

    @Published private(set) var queries: [String] = []

    private init() {
        queries = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func add(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        queries.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        queries.insert(q, at: 0)
        if queries.count > limit { queries = Array(queries.prefix(limit)) }
        save()
    }

    func remove(_ query: String) {
        queries.removeAll { $0 == query }
        save()
    }

    func clear() {
        queries = []
        save()
    }

    /// History entries that match what's been typed so far, as Android shows
    /// above the live suggestions.
    func matching(_ query: String, limit: Int = 3) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return queries.filter { $0.lowercased().contains(q) && $0.lowercased() != q }
            .prefix(limit).map { $0 }
    }

    private func save() {
        UserDefaults.standard.set(queries, forKey: key)
    }
}
