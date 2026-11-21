import Foundation

// The offline search, run on Linux as Android's OfflineSongsTest runs it.

struct Song { let title: String; let artist: String; let album: String? }

func find(_ query: String, _ songs: [Song]) -> [String] {
    OfflineSearch.search(query, in: songs, title: \.title, others: { [$0.artist, $0.album] }).map(\.title)
}

var failed = false
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok   \(what)" : "  FAIL \(what)")
    if !ok { failed = true }
}

let songs = [
    Song(title: "Love On Top", artist: "Beyoncé", album: "4"),
    Song(title: "Halo", artist: "Beyoncé", album: "I Am... Sasha Fierce"),
    Song(title: "Crazy in Love", artist: "Beyoncé", album: "Dangerously in Love"),
    Song(title: "Lovely", artist: "Billie Eilish", album: nil),
    Song(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours"),
    Song(title: "Resham Firiri", artist: "Nepali Folk", album: nil),
]

check(find("beyonce", songs) == ["Love On Top", "Halo", "Crazy in Love"], "accents and capitals do not matter")
check(find("LOVE", songs) == ["Love On Top", "Lovely", "Crazy in Love"],
      "titles starting with it first, then titles holding it, then the rest")
check(find("halo beyonce", songs) == ["Halo"], "every word has to match, across title and artist")
check(find("after hours", songs) == ["Blinding Lights"], "the album counts")
check(find("weeknd love", songs).isEmpty, "a word that matches nothing leaves nothing")
check(find("   ", songs).isEmpty, "blank finds nothing")
check(find("  resham  ", songs) == ["Resham Firiri"], "spaces round it are ignored")

print(failed ? "\nFailed." : "\nAll good.")
exit(failed ? 1 : 0)
