import Foundation

/// Covers for the Browse tiles, so each one shows what is behind it rather than a
/// flat colour.
///
/// A tile's contents barely change week to week, and fetching them every time the
/// search screen opens would be a page of requests for decoration. So three covers
/// per tile are chosen once and kept for a week.
@MainActor
final class BrowseArt: ObservableObject {
    static let shared = BrowseArt()

    /// How many covers a tile fans out.
    static let covers = 3

    @Published private(set) var art: [String: [String]] = [:]

    private let keep: TimeInterval = 7 * 24 * 60 * 60
    private let artKey = "browseArt"
    private let savedAtKey = "browseArtSavedAt"
    private var loading: Set<String> = []

    private init() {
        let savedAt = UserDefaults.standard.double(forKey: savedAtKey)
        guard savedAt > 0, Date().timeIntervalSince1970 - savedAt < keep else { return }
        art = (UserDefaults.standard.dictionary(forKey: artKey) as? [String: [String]]) ?? [:]
    }

    static func key(_ mood: MoodItem) -> String {
        "\(mood.browseId ?? "")|\(mood.params ?? "")"
    }

    /// Fills in anything missing, one tile at a time, and writes the lot down once.
    func warm(for moods: [MoodItem]) {
        for mood in moods {
            let k = Self.key(mood)
            guard art[k] == nil, !loading.contains(k), let browseId = mood.browseId else { continue }
            loading.insert(k)
            Task {
                let items = await YouTube.moodPlaylists(browseId: browseId, params: mood.params)
                let covers = items.compactMap { $0.thumbnail.isEmpty ? nil : $0.thumbnail }
                    .prefix(Self.covers)
                loading.remove(k)
                guard !covers.isEmpty else { return }
                art[k] = Array(covers)
                save()
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(art, forKey: artKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: savedAtKey)
    }
}
