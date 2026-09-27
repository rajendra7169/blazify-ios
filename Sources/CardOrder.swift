import Foundation

/// The order a greeting-card button offers its songs in, and where it starts.
///
/// The Android card gives every song a fixed random place the first time it is
/// seen and keeps those places in a map, so a list that reloads keeps its order.
/// This does the same thing without the map: the place is worked out from the
/// song's own id, so it is the same place every time — across a reload, and
/// across a restart, which Android's version does not manage.
///
/// It is deliberately free of everything but Foundation, so it can be compiled
/// and run on a machine with no Xcode. The bug it exists to prevent — a button
/// playing a different song from the one on its cover — is worth a test.
enum CardOrder {
    /// A song's fixed place in the running order: somewhere in 0..<1, decided by
    /// its id alone. FNV-1a, because it only has to be arbitrary and stable.
    static func place(_ id: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Double(hash % 1_000_003) / 1_000_003
    }

    /// `items` in their fixed order, turned so that `cover` is first.
    ///
    /// The song on the button is always the first of what this returns, which is
    /// what lets the button hand the player this exact list and start at 0. A
    /// cover that is no longer in the list starts from the song that took its
    /// place in the order, not from the top.
    static func order<T>(_ items: [T], id: (T) -> String, from cover: String?) -> [T] {
        let sorted = items.sorted { place(id($0)) < place(id($1)) }
        guard let cover, !sorted.isEmpty else { return sorted }
        let coverPlace = place(cover)
        let start = sorted.firstIndex { place(id($0)) >= coverPlace } ?? 0
        return Array(sorted[start...]) + Array(sorted[..<start])
    }

    /// What the button should offer next, once `order` has been played.
    static func next<T>(after order: [T], id: (T) -> String) -> String? {
        order.dropFirst().first.map(id)
    }
}
