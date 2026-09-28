import Foundation

// A copy of Letterbox, checked against frames made by hand.
enum Letterbox {
    static let dark: Double = 24
    static let printShare = 0.25
    static let smallest = 0.04
    static let largest = 0.22

    static func share(rows: [[Double]]) -> Double? {
        guard let width = rows.first?.count, width > 0, rows.count > 4 else { return nil }
        func isBand(_ row: [Double]) -> Bool {
            row.filter { $0 >= dark }.count <= Int(Double(width) * printShare)
        }
        var top = 0
        while top < rows.count / 2, isBand(rows[top]) { top += 1 }
        var bottom = 0
        while bottom < rows.count / 2, isBand(rows[rows.count - 1 - bottom]) { bottom += 1 }
        let share = Double(min(top, bottom)) / Double(rows.count)
        if share > largest { return nil }
        return share >= smallest ? share : 0
    }
    static func zoom(for share: Double) -> Double { share > 0 ? 1 / (1 - 2 * share) : 1 }
}

/// A frame: `lines` rows, the first and last `band` of them black.
func frame(lines: Int = 54, band: Int, bright: Double = 180, printed: Int = 0) -> [[Double]] {
    (0..<lines).map { line in
        let isBand = line < band || line >= lines - band
        return (0..<48).map { column in
            if !isBand { return bright }
            // A label's name printed in the band covers a few columns.
            return column < printed ? 200 : 2
        }
    }
}

var bad = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok { print("  ok   \(name)") } else { print("  FAIL \(name) \(detail)"); bad += 1 }
}
func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.001 } ?? false }

let noBands = Letterbox.share(rows: frame(band: 0))
check("a picture with no bands is left alone", near(noBands, 0))
check("and is not zoomed", Letterbox.zoom(for: noBands ?? 0) == 1)

let thin = Letterbox.share(rows: frame(band: 1))
check("a single dark line is not a band", near(thin, 0), "\(thin as Any)")

let cinema = Letterbox.share(rows: frame(band: 7))   // 7/54 ≈ 13% each side
check("a cinema-shaped picture is measured", near(cinema, 7.0 / 54))
let z = Letterbox.zoom(for: cinema ?? 0)
check("and zoomed just past its bands", abs(z - 1 / (1 - 2 * (7.0 / 54))) < 0.001)
check("which is a modest zoom, not a crop", z > 1.2 && z < 1.4, "\(z)")

check("a frame that is dark nearly all over says nothing",
      Letterbox.share(rows: frame(band: 26)) == nil)

check("a name printed in the band is still a band",
      near(Letterbox.share(rows: frame(band: 7, printed: 8)), 7.0 / 54))
check("but a bright strip across it is not",
      near(Letterbox.share(rows: frame(band: 7, printed: 40)), 0))

// Bands only at the top (a dark sky) must not be taken for letterboxing.
var sky = frame(band: 0)
for line in 0..<7 { sky[line] = Array(repeating: 2, count: 48) }
check("darkness at the top alone is not a band", near(Letterbox.share(rows: sky), 0))

print(bad == 0 ? "\nAll good." : "\n\(bad) FAILED")
exit(bad == 0 ? 0 : 1)
