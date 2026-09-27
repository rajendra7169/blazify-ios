import Foundation

// The real Sources/CardOrder.swift is compiled alongside this file.
struct Song { let videoId: String; let title: String }
func ids(_ s: [Song]) -> [String] { s.map(\.videoId) }

var failures = 0
func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition { print("  ok   \(name)") }
    else { print("  FAIL \(name) \(detail)"); failures += 1 }
}

let pool = (1...8).map { Song(videoId: "id\($0)", title: "Song \($0)") }

print("The cover is always what plays first")
var cover: String? = nil
var order = CardOrder.order(pool, id: \.videoId, from: cover)
check("a fresh card offers something", !order.isEmpty)
// Walk the whole list the way pressing the button does, eight times over.
var seen: [String] = []
for _ in 0..<8 {
    order = CardOrder.order(pool, id: \.videoId, from: cover)
    let playing = order.first!.videoId          // what the player is handed at index 0
    let shown = order.first!.videoId            // what the cover draws
    check("press: plays the song on the cover (\(shown))", playing == shown)
    seen.append(playing)
    cover = CardOrder.next(after: order, id: \.videoId)
}
check("eight presses gave eight different songs", Set(seen).count == 8, "\(seen)")
check("and then it comes back round", CardOrder.order(pool, id: \.videoId, from: cover).first!.videoId == seen[0])

print("\nThe order holds when the list reloads")
let reloaded = pool.shuffled()
check("same songs, same order",
      ids(CardOrder.order(pool, id: \.videoId, from: "id3"))
      == ids(CardOrder.order(reloaded, id: \.videoId, from: "id3")))

print("\nOne button does not move the other")
var forYou: String? = "id2"
var speed: String? = "id5"
let before = CardOrder.order(pool, id: \.videoId, from: speed).first!.videoId
forYou = CardOrder.next(after: CardOrder.order(pool, id: \.videoId, from: forYou), id: \.videoId)
check("pressing For you left the speed dial where it was",
      CardOrder.order(pool, id: \.videoId, from: speed).first!.videoId == before)
check("and For you itself moved on", forYou != "id2")

print("\nAwkward cases")
check("an empty list gives nothing", CardOrder.order([Song](), id: \.videoId, from: "id1").isEmpty)
check("one song is its own cover", CardOrder.order([pool[0]], id: \.videoId, from: nil).count == 1)
let gone = CardOrder.order(pool, id: \.videoId, from: "a-song-no-longer-here")
check("a cover that left the list still plays something", gone.count == 8)
check("nothing is lost from the list", Set(ids(CardOrder.order(pool, id: \.videoId, from: "id7"))) == Set(ids(pool)))
check("a place is the same every time", CardOrder.place("id1") == CardOrder.place("id1"))

print(failures == 0 ? "\nAll good." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
