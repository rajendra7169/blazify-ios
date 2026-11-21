import Foundation

/// Searching the songs that play with no connection, where YouTube cannot be
/// asked. Plain Foundation and nothing of the app's, so it is checked and run
/// on Linux (scripts/offlinesearch-test).
enum OfflineSearch {
    /// Lower case, without accents, so "Beyoncé" is found by typing "beyonce".
    static func searchable(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    /// The items whose title or other fields (artist, album) hold every word
    /// of `query`, best first: titles that start with what was typed, then
    /// titles that hold it, then the rest in their own order.
    static func search<T>(_ query: String, in items: [T],
                          title: (T) -> String, others: (T) -> [String?]) -> [T] {
        let typed = searchable(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = typed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        var ranked: [(rank: Int, order: Int, item: T)] = []
        for (order, item) in items.enumerated() {
            let name = searchable(title(item))
            let all = ([name] + others(item).compactMap { $0 }.map(searchable)).joined(separator: " ")
            guard words.allSatisfy({ all.contains($0) }) else { continue }
            let rank = name.hasPrefix(typed) ? 0 : (name.contains(typed) ? 1 : 2)
            ranked.append((rank, order, item))
        }
        // Sorted on both, so equal ranks keep the order they came in.
        ranked.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.order < $1.order }
        return ranked.map(\.item)
    }
}
