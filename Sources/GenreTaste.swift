import Foundation
import SwiftUI

/// Blazify Project (C) 2026
/// Licensed under GPL-3.0

/// Which genre tiles are this listener's.
///
/// YouTube's list of genres is the same for everybody in the country — in
/// Nepal it runs to Kannada, Malayalam and Marathi whether or not anybody in
/// the house has ever played a note of them — and it comes in no order but
/// the alphabet. YouTube keeps no "for you" ordering of it to ask for. But each
/// genre's page carries fifty of its songs with their artists, and the player
/// keeps a history of who was played: a genre whose page names the listener's
/// artists is theirs, and one that names none of them is not.
///
/// So the genre pages are read through once a day, quietly, and each genre is
/// scored by how much of the listener's history its artists account for. What
/// the listener actually opens counts too, so a genre they go to by hand rises
/// without having to be deduced. Moods are left alone: Chill is for everybody.
@MainActor
final class GenreTaste: ObservableObject {
    static let shared = GenreTaste()

    /// Score per genre title. Only genres with a score above zero are placed
    /// ahead of YouTube's order; the rest keep it.
    @Published private(set) var scores: [String: Double] = [:]

    /// The artists named on each genre's page, lowercased, from the last read.
    private var artistsByGenre: [String: [String]]
    private var scannedAt: Date?
    /// Tiles opened by hand, weighted as if they were plays.
    private var opened: [String: Double]
    private var scanning = false

    private let keepFor: TimeInterval = 24 * 60 * 60
    /// One tap on a tile is worth this many plays of an artist found there.
    private let openWeight: Double = 4
    /// How many of the listener's artists are matched against each page.
    private let artistsConsidered = 40

    private init() {
        let d = UserDefaults.standard
        artistsByGenre = (try? JSONDecoder().decode([String: [String]].self,
                                                    from: d.data(forKey: "genreTasteArtists") ?? Data())) ?? [:]
        scannedAt = d.object(forKey: "genreTasteScannedAt") as? Date
        opened = (try? JSONDecoder().decode([String: Double].self,
                                            from: d.data(forKey: "genreTasteOpened") ?? Data())) ?? [:]
        rescore()
    }

    /// The tiles with the listener's genres first: those with a score, by
    /// score; then the rest in the order YouTube gave. Moods keep their place.
    func order(_ tiles: [MoodItem]) -> [MoodItem] {
        let moods = tiles.filter { !$0.isGenre }
        let genres = tiles.filter(\.isGenre)
        let ranked = genres.enumerated().sorted { a, b in
            let sa = scores[a.element.title] ?? 0, sb = scores[b.element.title] ?? 0
            if sa != sb { return sa > sb }
            return a.offset < b.offset
        }.map(\.element)
        return moods + ranked
    }

    /// How many genres are the listener's — those with any score at all.
    func count(of tiles: [MoodItem]) -> Int {
        tiles.filter { $0.isGenre && (scores[$0.title] ?? 0) > 0 }.count
    }

    /// A tile opened by hand. Counts whether or not its page is ever read.
    func noteOpened(_ tile: MoodItem) {
        guard tile.isGenre else { return }
        opened[tile.title, default: 0] += 1
        if let data = try? JSONEncoder().encode(opened) {
            UserDefaults.standard.set(data, forKey: "genreTasteOpened")
        }
        rescore()
    }

    /// Reads the genre pages through if the last read is a day old, a few at a
    /// time so the Browse page does not announce itself to YouTube as a burst.
    func refresh(_ tiles: [MoodItem]) async {
        let genres = tiles.filter(\.isGenre)
        guard !genres.isEmpty, !scanning else { return }
        if let scannedAt, Date().timeIntervalSince(scannedAt) < keepFor,
           genres.allSatisfy({ artistsByGenre[$0.title] != nil }) {
            return
        }
        scanning = true
        defer { scanning = false }

        var found: [String: [String]] = [:]
        // Three at a time: the pages are small, and thirty-five of them in one
        // go is the shape of a scraper rather than of somebody browsing.
        for group in stride(from: 0, to: genres.count, by: 3) {
            let batch = Array(genres[group ..< min(group + 3, genres.count)])
            await withTaskGroup(of: (String, [String]).self) { tasks in
                for tile in batch {
                    tasks.addTask {
                        let page = await YouTube.shelfPage(browseId: tile.browseId ?? "", params: tile.params)
                        return (tile.title, Self.artistNames(in: page.items))
                    }
                }
                for await (title, names) in tasks { found[title] = names }
            }
        }
        guard !found.isEmpty else { return }
        for (title, names) in found { artistsByGenre[title] = names }
        scannedAt = Date()
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(artistsByGenre) { d.set(data, forKey: "genreTasteArtists") }
        d.set(scannedAt, forKey: "genreTasteScannedAt")
        rescore()
    }

    /// Each genre's score: the plays of the listener's artists that its page
    /// names, plus the tiles opened by hand.
    private func rescore() {
        let top = PlayHistory.topArtists(.all, limit: artistsConsidered)
        var out: [String: Double] = [:]
        for (genre, names) in artistsByGenre {
            let on = Set(names)
            var score = 0.0
            for artist in top where on.contains(artist.name.lowercased()) {
                score += Double(artist.plays)
            }
            if score > 0 { out[genre] = score }
        }
        for (genre, times) in opened {
            out[genre, default: 0] += times * openWeight
        }
        scores = out
    }

    /// The artists a page's rows name, split apart where a row names several.
    /// A song row's subtitle is its artists; a card's is "Album • Artist" or
    /// "Playlist • YouTube Music", and taking every part of it is harmless —
    /// nobody's history has a play of "Album".
    nonisolated private static func artistNames(in items: [HomeItem]) -> [String] {
        var names: Set<String> = []
        for item in items {
            for part in item.subtitle.split(whereSeparator: { "•,&".contains($0) }) {
                let name = part.trimmingCharacters(in: .whitespaces).lowercased()
                if name.count > 1 { names.insert(name) }
            }
        }
        return Array(names)
    }
}
