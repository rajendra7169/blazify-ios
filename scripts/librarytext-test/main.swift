import Foundation

var bad = 0
func check(_ raw: String, _ want: String) {
    let got = LibraryCardText.subtitle(raw)
    if got == want { print("  ok   \(raw.isEmpty ? "(empty)" : raw) -> \(got)") }
    else { print("  FAIL \(raw) -> \(got), wanted \(want)"); bad += 1 }
}

check("Playlist • 26 songs", "26 songs")
check("YouTube Music • 50 songs", "50 songs")
check("Playlist • 1 song", "1 song")
check("Album • 2,145 songs", "2,145 songs")
check("Playlist", "Playlist")
check("Sushant KC", "Sushant KC")
check("Album • Sushant KC", "Sushant KC")
check("", "")
check("Podcast • 12 episodes", "12 episodes")
print(bad == 0 ? "\nAll good." : "\n\(bad) FAILED")
exit(bad == 0 ? 0 : 1)
