import Foundation

/// The 3D sound choices: off, Surround (speakers round you) and 8D (the song
/// circling your head). The raw values are Android's, so a setting carried
/// between the two reads the same.
enum SpatialSound: String, CaseIterable, Identifiable {
    case off = "OFF"
    case surround = "SURROUND"
    case orbit = "ORBIT"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return String(localized: "Off")
        case .surround: return String(localized: "Surround")
        case .orbit: return String(localized: "8D")
        }
    }

    /// What the setting's row says under its name.
    var blurb: String {
        switch self {
        case .off:
            return String(localized: "Off. Surround places the song round you; 8D sends it circling your head. Best with headphones")
        case .surround:
            return String(localized: "Surround: the song comes from speakers round you, with its width and room behind")
        case .orbit:
            return String(localized: "8D: the song slowly circles your head")
        }
    }
}

/// How the sound is placed round the listener.
enum SpatialMode {
    /// Surround: five speakers round you, as in a cinema. Left, centre and
    /// right in front; the width and the room of the song from two speakers
    /// behind.
    case speakers
    /// The pair of speakers slowly travels round your head.
    case orbit
}

/// Turns stereo sound into sound that comes from round the head. Each channel
/// is played from a virtual speaker, and each ear hears each speaker the way it
/// would in a room: the speaker on the other side a moment later, quieter and
/// duller (the head is in the way), darker from behind, with a few wall echoes
/// and a little room after it so the sound sits outside the head.
///
/// Runs on the audio thread, a buffer at a time: every buffer it needs is
/// allocated here in `init` (the tap's prepare), and `process` allocates
/// nothing, takes no lock and calls nothing that might.
final class Spatializer {
    var mode: SpatialMode = .speakers
    /// Seconds for one trip round the head in 8D.
    var orbitSeconds = 12.0

    private let rate: Double
    private let sources: [SpatialSource]
    private let centre: SpatialSource
    private let rears: [SpatialSource]
    private let roomRears: [SpatialSource]
    private let rearLine: SpatialDelay
    private var rearLow = 0.0
    private let echoes: [SpatialSource]
    private let echoLine: SpatialDelay
    private let echoLineR: SpatialDelay
    private let room: SpatialRoom
    private var time: Int64 = 0

    private static let front = Double.pi / 5.2
    private static let rear = Double.pi * 0.64
    private static let rearDelay = 0.014
    private static let rearGain = 0.9
    private static let orbitSpread = Double.pi / 9
    private static let echoDelays: (Double, Double, Double, Double) = (0.009, 0.011, 0.017, 0.021)
    private static let echoGains: (Double, Double, Double, Double) = (0.28, 0.28, 0.18, 0.18)
    private static let echoAngles: (Double, Double, Double, Double) = (Double.pi * 0.4, Double.pi * 0.4,
                                                                       Double.pi * 0.6, Double.pi * 0.6)
    private static let gain = 0.72

    init(rate: Int) {
        let r = max(rate, 8_000)
        self.rate = Double(r)
        sources = [SpatialSource(rate: r), SpatialSource(rate: r)]
        centre = SpatialSource(rate: r)
        rears = [SpatialSource(rate: r), SpatialSource(rate: r)]
        roomRears = [SpatialSource(rate: r), SpatialSource(rate: r)]
        rearLine = SpatialDelay(size: Int(Double(r) * 0.03) + 2)
        echoes = [SpatialSource(rate: r), SpatialSource(rate: r), SpatialSource(rate: r), SpatialSource(rate: r)]
        echoLine = SpatialDelay(size: Int(Double(r) * 0.05) + 2)
        echoLineR = SpatialDelay(size: Int(Double(r) * 0.05) + 2)
        room = SpatialRoom(rate: r)
    }

    /// Forgets every echo and tail, so sound switched back on after a while
    /// off doesn't start with the last of what played before.
    func clear() {
        for s in sources { s.clear() }
        centre.clear()
        for s in rears { s.clear() }
        for s in roomRears { s.clear() }
        for s in echoes { s.clear() }
        rearLine.clear()
        echoLine.clear()
        echoLineR.clear()
        room.clear()
        rearLow = 0
    }

    private static func echo(_ k: Int, _ t: (Double, Double, Double, Double)) -> Double {
        switch k {
        case 0: return t.0
        case 1: return t.1
        case 2: return t.2
        default: return t.3
        }
    }

    /// Processes `frames` frames in place. `left` and `right` step by `stride`
    /// samples, so the same code serves separate channel buffers (stride 1)
    /// and one interleaved buffer (stride 2, right = left + 1).
    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                 stride: Int, frames: Int) {
        let orbit = mode == .orbit
        var f = 0
        while f < frames {
            let i = f * stride
            let l = Double(left[i])
            let r = Double(right[i])
            let turn = orbit
                ? 2 * Double.pi * (Double(time) / rate / orbitSeconds).truncatingRemainder(dividingBy: 1)
                : 0
            time &+= 1
            var outL = 0.0
            var outR = 0.0
            if orbit {
                // The song as one sound travelling round, a little wide so it
                // stays stereo.
                let a = sources[0].render(l, angle: turn - Self.orbitSpread)
                outL += a.0; outR += a.1
                let b = sources[1].render(r, angle: turn + Self.orbitSpread)
                outL += b.0; outR += b.1
            } else {
                // Surround: what both channels share goes to the centre, the
                // rest to the front pair, and the difference between them (the
                // song's width and room) to the pair behind, a moment later.
                let mid = (l + r) * 0.5
                let sideSig = (l - r) * 0.5
                let a = sources[0].render(l - 0.35 * mid, angle: -Self.front)
                outL += a.0; outR += a.1
                let b = sources[1].render(r - 0.35 * mid, angle: Self.front)
                outL += b.0; outR += b.1
                let c = centre.render(mid * 0.55, angle: 0)
                outL += c.0; outR += c.1
                rearLine.push(sideSig)
                let late = rearLine.read(Self.rearDelay * rate)
                rearLow += 0.35 * (late - rearLow)
                let d = rears[0].render(rearLow * Self.rearGain, angle: -Self.rear)
                outL += d.0; outR += d.1
                let e = rears[1].render(-rearLow * Self.rearGain, angle: Self.rear)
                outL += e.0; outR += e.1
            }
            // Echoes off the side walls, arriving from wider angles a few
            // milliseconds later.
            echoLine.push(l)
            echoLineR.push(r)
            for k in 0..<4 {
                let fromLeft = k % 2 == 0
                let delay = Self.echo(k, Self.echoDelays) * rate
                let s = (fromLeft ? echoLine : echoLineR).read(delay) * Self.echo(k, Self.echoGains)
                let angle = turn + (fromLeft ? -1 : 1) * Self.echo(k, Self.echoAngles)
                let e = echoes[k].render(s, angle: angle)
                outL += e.0; outR += e.1
            }
            // A small room after it all. In surround it comes from behind, so
            // even a song that's the same in both channels has something round
            // you.
            let (wl, wr) = room.process(l + r)
            if orbit {
                outL += wl
                outR += wr
            } else {
                let a = roomRears[0].render(wl * 1.8, angle: -Self.rear - 0.3)
                outL += a.0; outR += a.1
                let b = roomRears[1].render(wr * 1.8, angle: Self.rear + 0.3)
                outL += b.0; outR += b.1
            }
            left[i] = Float(Self.soft(outL * Self.gain))
            right[i] = Float(Self.soft(outR * Self.gain))
            f += 1
        }
    }

    @inline(__always)
    private static func soft(_ x: Double) -> Double { abs(x) < 0.9 ? x : tanh(x) }
}

/// One sound at an angle round the head, as heard by each ear.
final class SpatialSource {
    private let line: SpatialDelay
    private let sampleTime: Double
    /// Splits each ear's sound at about 1.2 kHz: the head hides treble, but
    /// bass bends round it.
    private let split: Double
    private var farLow = 0.0
    private var nearLow = 0.0
    private var shadowLow = 0.0
    private var darkL = 0.0
    private var darkR = 0.0
    // The angle's sums, kept while it stays put (in Surround it always does).
    private var lastAngle = Double.nan
    private var side = 0.0
    private var front = 1.0
    private var lag = 0.0

    init(rate: Int) {
        line = SpatialDelay(size: Int(Double(rate) * 0.0012) + 4)
        sampleTime = 1.0 / Double(rate)
        split = 1 - exp(-2 * Double.pi * 1200.0 / Double(rate))
    }

    func clear() {
        line.clear()
        farLow = 0; nearLow = 0; shadowLow = 0; darkL = 0; darkR = 0
    }

    /// Left and right ear for `x` coming from `angle` radians clockwise from
    /// straight ahead.
    @inline(__always)
    func render(_ x: Double, angle: Double) -> (Double, Double) {
        line.push(x)
        if angle != lastAngle {
            lastAngle = angle
            side = sin(angle)
            front = cos(angle)
            // Woodworth's round head: how much later it reaches the far ear.
            lag = 0.0875 / 343.0 * (abs(asin(min(max(side, -1), 1))) + abs(side)) / sampleTime
        }
        let far = line.read(lag)
        let shade = abs(side)
        // Far ear: the bass nearly whole, the treble hidden by the head, the
        // more so the more to one side.
        farLow += split * (far - farLow)
        let farHigh = far - farLow
        shadowLow += (0.9 - 0.75 * shade) * (farHigh - shadowLow)
        let farEar = farLow * (1 - 0.18 * shade) + shadowLow * (1 - 0.8 * shade)
        // Near ear: a touch brighter as the sound turns towards it.
        nearLow += split * (x - nearLow)
        let nearHigh = x - nearLow
        // In front, the outer ear lifts the presence a little; behind, it
        // hides it.
        let presence = 0.18 * front
        let nearEar = nearLow + nearHigh * (1 + 0.25 * shade + presence)
        let farEarLit = farEar + (far - farLow) * presence * (1 - shade) * 0.5
        var left = side >= 0 ? farEarLit : nearEar
        var right = side >= 0 ? nearEar : farEarLit
        let behind = max(-front, 0)
        if behind > 0 {
            let k = 0.2 + 0.6 * (1 - behind)
            darkL += k * (left - darkL)
            darkR += k * (right - darkR)
            left = left * (1 - 0.4 * behind) + darkL * 0.4 * behind
            right = right * (1 - 0.4 * behind) + darkR * 0.4 * behind
        } else {
            darkL = left
            darkR = right
        }
        return (left, right)
    }
}

/// A short delay line that can be read between samples. Its memory is taken
/// once, when it is made.
final class SpatialDelay {
    private let buffer: UnsafeMutablePointer<Double>
    private let size: Int
    private var at = 0

    init(size: Int) {
        self.size = max(size, 3)
        buffer = UnsafeMutablePointer<Double>.allocate(capacity: self.size)
        buffer.initialize(repeating: 0, count: self.size)
    }

    deinit { buffer.deallocate() }

    func clear() {
        for i in 0..<size { buffer[i] = 0 }
        at = 0
    }

    @inline(__always)
    func push(_ x: Double) {
        buffer[at] = x
        at += 1
        if at == size { at = 0 }
    }

    /// The sample `samples` ago (0 = the one just pushed).
    @inline(__always)
    func read(_ samples: Double) -> Double {
        let back = min(max(samples, 0), Double(size) - 2)
        let whole = Int(back)
        let frac = back - Double(whole)
        let i0 = (at - 1 - whole + size * 2) % size
        let i1 = (i0 - 1 + size) % size
        return buffer[i0] * (1 - frac) + buffer[i1] * frac
    }
}

/// A small, soft room: a few feedback combs and all-passes for each ear, a
/// little different on each side so the two ears don't hear the same tail
/// (Schroeder's reverb).
final class SpatialRoom {
    private let combsL: [SpatialComb]
    private let combsR: [SpatialComb]
    private let passL: [SpatialAllPass]
    private let passR: [SpatialAllPass]
    private let pre: SpatialRing
    private static let wet = 1.0

    init(rate: Int) {
        let scale = Double(rate) / 44_100.0
        combsL = [1116, 1188, 1277, 1356].map { SpatialComb(size: Int(Double($0) * scale)) }
        combsR = [1139, 1211, 1300, 1379].map { SpatialComb(size: Int(Double($0) * scale)) }
        passL = [556, 441].map { SpatialAllPass(size: Int(Double($0) * scale)) }
        passR = [579, 464].map { SpatialAllPass(size: Int(Double($0) * scale)) }
        pre = SpatialRing(size: Int(Double(rate) * 0.012))
    }

    func clear() {
        for c in combsL { c.clear() }
        for c in combsR { c.clear() }
        for p in passL { p.clear() }
        for p in passR { p.clear() }
        pre.clear()
    }

    @inline(__always)
    func process(_ x: Double) -> (Double, Double) {
        let input = pre.swap(x) * 0.015
        var l = 0.0
        var r = 0.0
        for k in 0..<combsL.count { l += combsL[k].process(input) }
        for k in 0..<combsR.count { r += combsR[k].process(input) }
        for k in 0..<passL.count { l = passL[k].process(l) }
        for k in 0..<passR.count { r = passR[k].process(r) }
        return (l * Self.wet, r * Self.wet)
    }
}

/// A plain ring of samples: what goes in comes out `size` samples later.
final class SpatialRing {
    fileprivate let buffer: UnsafeMutablePointer<Double>
    fileprivate let size: Int
    fileprivate var at = 0

    init(size: Int) {
        self.size = max(size, 1)
        buffer = UnsafeMutablePointer<Double>.allocate(capacity: self.size)
        buffer.initialize(repeating: 0, count: self.size)
    }

    deinit { buffer.deallocate() }

    func clear() {
        for i in 0..<size { buffer[i] = 0 }
        at = 0
    }

    /// Hands back the oldest sample and keeps `x` in its place.
    @inline(__always)
    func swap(_ x: Double) -> Double {
        let out = buffer[at]
        buffer[at] = x
        at += 1
        if at == size { at = 0 }
        return out
    }
}

/// A feedback comb whose walls soak up the treble.
final class SpatialComb {
    private let ring: SpatialRing
    private var low = 0.0

    init(size: Int) { ring = SpatialRing(size: size) }

    func clear() { ring.clear(); low = 0 }

    @inline(__always)
    func process(_ x: Double) -> Double {
        let out = ring.buffer[ring.at]
        low = out * 0.6 + low * 0.4
        _ = ring.swap(x + low * 0.78)
        return out
    }
}

/// An all-pass that smears the comb's echoes into a tail.
final class SpatialAllPass {
    private let ring: SpatialRing

    init(size: Int) { ring = SpatialRing(size: size) }

    func clear() { ring.clear() }

    @inline(__always)
    func process(_ x: Double) -> Double {
        let held = ring.buffer[ring.at]
        _ = ring.swap(x + held * 0.5)
        return -x + held
    }
}
