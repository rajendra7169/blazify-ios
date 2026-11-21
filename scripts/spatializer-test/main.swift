import Foundation

// Runs the 3D sound engine on Linux, as Android's SpatializerTest does. On
// iOS String(localized:) comes from Foundation; here it is a stand-in.
extension String { init(localized s: String) { self = s } }

func level(_ x: [Float], _ channel: Int) -> Double {
    var sum = 0.0
    var n = 0
    for i in Swift.stride(from: channel, to: x.count, by: 2) {
        sum += Double(x[i]) * Double(x[i])
        n += 1
    }
    return sqrt(sum / Double(n))
}

func run(_ engine: Spatializer, _ input: [Float], frames: Int) -> [Float] {
    var buffer = input
    buffer.withUnsafeMutableBufferPointer { p in
        engine.process(left: p.baseAddress!, right: p.baseAddress! + 1, stride: 2, frames: frames)
    }
    return buffer
}

var failed = false
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok   \(what)" : "  FAIL \(what)")
    if !ok { failed = true }
}

// A speaker on the left is heard by both ears, the left more.
do {
    let rate = 48_000
    var input = [Float](repeating: 0, count: rate * 2)
    for f in 0..<rate { input[f * 2] = Float(0.5 * sin(2 * Double.pi * 440 * Double(f) / Double(rate))) }
    let out = run(Spatializer(rate: rate), input, frames: rate)
    let l = level(out, 0), r = level(out, 1)
    check(out.allSatisfy { $0.isFinite && abs($0) <= 1 }, "stays finite and within full scale")
    check(l > r * 1.3 && r > l * 0.2, "left-only sound stays left but reaches the other ear (L \(l), R \(r))")
}

// 8D: right-heavy while the sound is on the right, left-heavy on the way back.
do {
    let rate = 48_000
    let engine = Spatializer(rate: rate)
    engine.mode = .orbit
    engine.orbitSeconds = 4
    var seed: UInt64 = 3
    func noise() -> Float {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Float(Double(seed >> 11) / Double(1 << 53) * 0.6 - 0.3)
    }
    var ratios: [Double] = []
    for _ in 0..<4 {
        var input = [Float](repeating: 0, count: rate * 2)
        for i in 0..<input.count { input[i] = noise() }
        let out = run(engine, input, frames: rate)
        ratios.append(level(out, 1) / level(out, 0))
    }
    check(ratios[0] > 1.1 && ratios[1] > 1.1 && ratios[2] < 0.9 && ratios[3] < 0.9,
          "8D moves the sound round the head (\(ratios.map { String(format: "%.2f", $0) }))")
}

print(failed ? "\nFailed." : "\nAll good.")
exit(failed ? 1 : 0)
