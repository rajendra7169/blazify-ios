import Foundation

/// What a library card says under its name.
///
/// Android's library cards read "26 songs" — the one fact that tells you what
/// you are about to open. YouTube's own subtitle for the same row is whatever it
/// feels like that day: "Playlist", "Playlist • 26 songs", "YouTube Music • 50
/// songs". This takes the count when there is one and drops the kind of thing it
/// is, which the card's own shape already says.
enum LibraryCardText {
    static func subtitle(_ raw: String) -> String {
        let parts = raw
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // A count, wherever it sits: "26 songs", "1 song", "50 tracks".
        if let count = parts.first(where: { looksLikeCount($0) }) { return count }
        // Otherwise anything that is not just the word for what it is.
        let kinds = ["playlist", "album", "single", "ep", "artist", "podcast"]
        if let rest = parts.first(where: { !kinds.contains($0.lowercased()) }) { return rest }
        return parts.first ?? raw
    }

    private static func looksLikeCount(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count == 2, let first = words.first, let unit = words.last else { return false }
        let number = first.replacingOccurrences(of: ",", with: "")
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return false }
        return ["song", "songs", "track", "tracks", "episode", "episodes"].contains(unit.lowercased())
    }
}
