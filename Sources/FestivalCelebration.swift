import SwiftUI

/// Blazify Project (C) 2026
/// Licensed under GPL-3.0

/// A few seconds of celebration over the whole screen when the festival logo is tapped: the
/// festival's own scene around the big moving logo, its greeting, and a way to turn festive
/// mode off. Everything is drawn here as a function of time, as on Android, so it adds no
/// pictures or animation files and costs nothing once it is closed. Any tap ends it early; with
/// Reduce Motion on it shows the finished picture and waits for a tap.
struct FestivalCelebration: View {
    let festival: Festival
    let country: String?
    var onDone: () -> Void
    /// The pill at the top right: festive mode off for good (Look & Feel turns it back on).
    var onTurnOff: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    /// When the fade out begins; until a tap it is near the end of the celebration.
    @State private var leaveAt: Date?

    /// How long the celebration stays before it fades by itself, in seconds.
    static let total = 6.5
    /// Where the big logo's centre sits, as a share of the screen's height.
    static let logoY: CGFloat = 0.36

    private var leaving: Date { leaveAt ?? start.addingTimeInterval(Self.total - 0.6) }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 3.2 : timeline.date.timeIntervalSince(start)
            let fade = reduceMotion ? 1 : min(max(1 - timeline.date.timeIntervalSince(leaving) / 0.5, 0), 1)
            ZStack(alignment: .topTrailing) {
                GeometryReader { geo in
                    scene(t: CGFloat(t), size: geo.size)
                }
                .ignoresSafeArea()
                turnOffPill
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            }
            .opacity(fade)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if reduceMotion { onDone() } else if Date() < leaving { leaveAt = Date() }
        }
        .task {
            guard !reduceMotion else { return }
            // Closes once the fade has run, whether it began by itself or with a tap.
            while !Task.isCancelled {
                if Date() >= leaving.addingTimeInterval(0.5) {
                    onDone()
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func scene(t: CGFloat, size: CGSize) -> some View {
        let logoSize = min(size.width * 0.46, 190)
        let logoCentre = size.height * Self.logoY
        // Below the logo; for Tihar and Diwali, below the rangoli round it.
        let textGap = festival == .diwali ? min(size.width, size.height) * 0.42 + 12 : logoSize / 2 + 24
        // The logo pops in, a little past full size and back.
        let pop = FestivalScene.backOut(min(max((t - 0.15) / 0.6, 0), 1))
        let textIn = min(max((t - 1.2) / 0.6, 0), 1)
        return ZStack(alignment: .topLeading) {
            Canvas { context, canvasSize in
                FestivalScene.draw(&context, festival: festival, t: t, size: canvasSize)
            }
            FestivalLogoArt(festival: festival, white: true)
                .frame(width: logoSize, height: logoSize)
                .scaleEffect(max(pop, 0.001))
                .opacity(Double(min(max(pop, 0), 1)))
                .position(x: size.width / 2, y: logoCentre)
            VStack(spacing: 0) {
                Text(LocalizedStringKey(festival.greeting(in: country)))
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: FestivalScene.greetingColors(festival),
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.45), radius: 5, y: 3)
                Text(LocalizedStringKey(festival == .diwali ? "Light, love and music to you and yours"
                                                             : "Joy, love and music to you and yours"))
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.88))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .frame(width: size.width)
            .scaleEffect(0.9 + 0.1 * textIn)
            .opacity(Double(textIn))
            .offset(y: logoCentre + textGap)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .combine)
    }

    private var turnOffPill: some View {
        Button(action: onTurnOff) {
            Text("Turn off festive mode")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// The scenes, worked out from the time alone, so nothing has to be kept between frames.
/// Sizes are in `u`, about one point per unit on a phone, the same unit Android's dp-sized
/// scene uses, so both lay out alike.
enum FestivalScene {
    private static let gold = FestivalArt.gold
    private static let paleGold = FestivalArt.paleGold
    private static let cream = Color(hex: 0xFFF59D)
    private static let amber = Color(hex: 0xFFA726)
    private static let coral = Color(hex: 0xFF7043)
    private static let clay = Color(hex: 0xB5532A)
    private static let clayLight = Color(hex: 0xE07A3F)
    private static let clayDark = Color(hex: 0x5A2614)

    /// The greeting's own festive colours.
    static func greetingColors(_ festival: Festival) -> [Color] {
        switch festival {
        case .diwali: [cream, amber, coral]
        case .halloween: [Color(hex: 0xFFCC80), Color(hex: 0xFF7043), Color(hex: 0xCE93D8)]
        case .christmas: [.white, Color(hex: 0xFFCDD2), Color(hex: 0xEF5350)]
        case .newYear: [gold, Color(hex: 0xF48FB1), Color(hex: 0x80DEEA)]
        case .musicDay: [Color(hex: 0xFF80AB), amber, Color(hex: 0xB388FF)]
        case .holi: [Color(hex: 0xFF4081), Color(hex: 0xFFEB3B), Color(hex: 0x69F0AE), Color(hex: 0x40C4FF), Color(hex: 0xE040FB)]
        case .dashain: [Color(hex: 0xFFF59D), Color(hex: 0xFFCA28), Color(hex: 0xFF8A65)]
        case .lunarNewYear, .eidAlFitr: [cream, gold, Color(hex: 0xFFB300)]
        case .eidAlAdha: [Color(hex: 0xC8E6C9), Color(hex: 0x81C784), gold]
        }
    }

    static func draw(_ context: inout GraphicsContext, festival: Festival, t: CGFloat, size: CGSize) {
        let u = min(size.width, size.height) / 360
        let centre = CGPoint(x: size.width / 2, y: size.height * FestivalCelebration.logoY)
        let dusk = min(max(t / 0.5, 0), 1)
        switch festival {
        case .diwali: lights(&context, t, u, centre, dusk, size)
        case .halloween: halloween(&context, t, u, dusk, size)
        case .christmas: christmas(&context, t, u, dusk, size)
        case .newYear: newYear(&context, t, u, dusk, size)
        case .musicDay: music(&context, t, u, dusk, size)
        case .holi, .dashain, .lunarNewYear, .eidAlFitr, .eidAlAdha:
            // No days yet, so they never show; a quiet sky should one ever be forced.
            sky(&context, dusk, Color(hex: 0x1A0B2E), Color(hex: 0x2A0E14), Color(hex: 0x0B0A09), size)
        }
    }

    // MARK: Scenes

    /// Tihar and Diwali: a rangoli blooms round the logo, sparks burst, diyas light along the bottom.
    private static func lights(_ c: inout GraphicsContext, _ t: CGFloat, _ u: CGFloat, _ centre: CGPoint, _ dusk: CGFloat, _ size: CGSize) {
        sky(&c, dusk, Color(hex: 0x1A0B2E), Color(hex: 0x2A0E14), Color(hex: 0x0B0A09), size)
        stars(&c, t, u, dusk, 40, cream, 0.62, size)
        let maxR = min(size.width, size.height) * 0.5
        let colors = [amber, Color(hex: 0xE91E63), Color(hex: 0x26A69A), Color(hex: 0xFFD54F)]
        for (k, petals) in [12, 16, 24].enumerated() {
            let grow = easeOut(min(max((t - 0.4 - CGFloat(k) * 0.22) / 0.7, 0), 1))
            if grow <= 0 { continue }
            let radius = maxR * (0.52 + 0.14 * CGFloat(k)) * grow
            let length = maxR * (0.12 + 0.02 * CGFloat(k)) * grow
            let turn = t * (k % 2 == 0 ? 6 : -6) + CGFloat(k) * 9
            let color = colors[k % colors.count]
            for i in 0 ..< petals {
                var turned = FestivalArt.rotated(c, turn + CGFloat(i) * 360 / CGFloat(petals), centre.x, centre.y)
                petal(&turned, CGPoint(x: centre.x, y: centre.y - radius + length), length, length * 0.42, color, u)
            }
            let ring = radius * 0.98
            c.stroke(Path(ellipseIn: CGRect(x: centre.x - ring, y: centre.y - ring, width: ring * 2, height: ring * 2)),
                     with: .color(color.opacity(0.35 * grow)), lineWidth: 2 * u)
        }
        // Sparks burst in the sky round the rangoli, never behind the logo.
        let sparks: [CGPoint] = [CGPoint(x: 0.18, y: 0.13), CGPoint(x: 0.82, y: 0.17), CGPoint(x: 0.22, y: 0.8), CGPoint(x: 0.78, y: 0.77)]
        for (b, at) in sparks.enumerated() {
            burst(&c, t, 0.9 + CGFloat(b) * 0.6, CGPoint(x: size.width * at.x, y: size.height * at.y),
                  [cream, amber, gold, Color(hex: 0xE91E63)], 48, 120 * u, 2.2, 70 * u, u, seed: b)
        }
        let count = 7
        let width = size.width / (CGFloat(count) + 1.5)
        for i in 0 ..< count {
            let lit = min(max((t - 0.7 - CGFloat(i) * 0.16) / 0.3, 0), 1)
            bottomDiya(&c, CGPoint(x: size.width * CGFloat(i + 1) / CGFloat(count + 1), y: size.height - width * 0.9),
                       width * 0.82, t * 1.3 + CGFloat(i) * 0.37, lit)
        }
    }

    /// Christmas: a winter night, strings of lights that twinkle, snow falling onto a snowy ground.
    private static func christmas(_ c: inout GraphicsContext, _ t: CGFloat, _ u: CGFloat, _ dusk: CGFloat, _ size: CGSize) {
        let w = size.width, h = size.height
        sky(&c, dusk, Color(hex: 0x0B1A33), Color(hex: 0x16294D), Color(hex: 0x0A0F1F), size)
        stars(&c, t, u, dusk, 30, .white, 0.5, size)
        let bulbColors = [Color(hex: 0xE53935), gold, Color(hex: 0x43A047), Color(hex: 0x1E88E5)]
        let rows: [(top: CGFloat, sag: CGFloat)] = [(0.06, 46), (0.13, 30)]
        for (row, string) in rows.enumerated() {
            let top = string.top, sag = string.sag
            var wire = Path()
            let n = 13
            for i in 0 ... 40 {
                let x = w * CGFloat(i) / 40
                let s = 2 * CGFloat(i) / 40 - 1
                let y = h * top + sag * u * (1 - s * s)
                if i == 0 { wire.move(to: CGPoint(x: x, y: y)) } else { wire.addLine(to: CGPoint(x: x, y: y)) }
            }
            c.stroke(wire, with: .color(Color(hex: 0x263238).opacity(dusk)), lineWidth: 2 * u)
            for i in 0 ..< n {
                let f = (CGFloat(i) + 0.5 + CGFloat(row) * 0.5) / CGFloat(n)
                let x = w * f
                let s = 2 * f - 1
                let y = h * top + sag * u * (1 - s * s) + 7 * u
                let on = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 3.2 + CGFloat(i) * 1.7 + CGFloat(row)))
                let bulb = bulbColors[(i + row) % bulbColors.count]
                FestivalArt.circle(&c, bulb.opacity(0.35 * on * dusk), 14 * u, x, y)
                FestivalArt.oval(&c, .color(bulb.opacity((0.5 + 0.5 * on) * dusk)), x - 4.5 * u, y - 6 * u, 9 * u, 12 * u)
                c.fill(Path(CGRect(x: x - 3 * u, y: y - 9 * u, width: 6 * u, height: 4 * u)),
                       with: .color(Color(hex: 0x455A64).opacity(dusk)))
            }
        }
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: h))
        ground.addLine(to: CGPoint(x: 0, y: h * 0.9))
        ground.addCurve(to: CGPoint(x: w, y: h * 0.87), control1: CGPoint(x: w * 0.3, y: h * 0.85), control2: CGPoint(x: w * 0.6, y: h * 0.93))
        ground.addLine(to: CGPoint(x: w, y: h))
        ground.closeSubpath()
        var snowy = c
        snowy.opacity = Double(dusk)
        snowy.fill(ground, with: FestivalArt.vertical([Color(hex: 0xE3F2FD), Color(hex: 0xB0BEC5)], h * 0.85, h))
        for i in 0 ..< 110 {
            let speed = (30 + 50 * hash(i, 1)) * u
            let y = (hash(i, 2) * h * 1.1 + t * speed).truncatingRemainder(dividingBy: h * 1.1) - h * 0.05
            let x = hash(i, 3) * w + sin(t * 0.9 + CGFloat(i)) * 14 * u
            FestivalArt.circle(&c, Color.white.opacity((0.5 + 0.5 * hash(i, 4)) * dusk), (1.5 + 3 * hash(i, 5)) * u, x, y)
        }
    }

    /// New Year: fireworks bursting all over a midnight sky, and confetti coming down.
    private static func newYear(_ c: inout GraphicsContext, _ t: CGFloat, _ u: CGFloat, _ dusk: CGFloat, _ size: CGSize) {
        sky(&c, dusk, Color(hex: 0x05061A), Color(hex: 0x140A33), Color(hex: 0x000000), size)
        stars(&c, t, u, dusk, 40, .white, 0.7, size)
        let palettes: [[Color]] = [
            [gold, cream, coral],
            [Color(hex: 0xEC407A), Color(hex: 0xF8BBD0), gold],
            [Color(hex: 0x26C6DA), Color(hex: 0xB388FF), .white],
            [Color(hex: 0x66BB6A), Color(hex: 0xFFEE58), .white],
        ]
        for k in 0 ..< 11 {
            let start = 0.3 + CGFloat(k) * 0.48
            let at = CGPoint(x: size.width * (0.15 + 0.7 * hash(k, 7)), y: size.height * (0.1 + 0.45 * hash(k, 8)))
            // The rocket climbs for half a second before it bursts.
            let climb = min(max((t - start + 0.5) / 0.5, 0), 1)
            if climb >= 0.01, climb <= 0.99 {
                let y = size.height - (size.height - at.y) * easeOut(climb)
                FestivalArt.line(&c, cream.opacity(0.8), at.x, y, at.x, y + 26 * u, 2.5 * u, round: true)
            }
            burst(&c, t, start, at, palettes[k % palettes.count], 56, 150 * u, 1.9, 60 * u, u, seed: k + 10)
        }
        confetti(&c, t, u, dusk, 70, size)
    }

    /// World Music Day: an equaliser dancing along the bottom, and notes floating up.
    private static func music(_ c: inout GraphicsContext, _ t: CGFloat, _ u: CGFloat, _ dusk: CGFloat, _ size: CGSize) {
        let w = size.width, h = size.height
        sky(&c, dusk, Color(hex: 0x1A0B3D), Color(hex: 0x3B0F5C), Color(hex: 0x0B0618), size)
        stars(&c, t, u, dusk, 30, Color(hex: 0xE1BEE7), 0.6, size)
        let bars = 24
        let gap = 4 * u
        let barWidth = (w - gap * CGFloat(bars + 1)) / CGFloat(bars)
        for i in 0 ..< bars {
            let level = 0.15 + 0.85 * abs(sin(t * (2.2 + hash(i, 1) * 2.5) + CGFloat(i) * 0.7))
            let barHeight = h * 0.2 * level * dusk
            guard barHeight > 0 else { continue }
            let x = gap + CGFloat(i) * (barWidth + gap)
            // Rounded no more than half its own height, as Android draws a short bar.
            let corner = min(barWidth / 2, barHeight / 2)
            c.fill(Path(roundedRect: CGRect(x: x, y: h - barHeight, width: barWidth, height: barHeight), cornerRadius: corner),
                   with: FestivalArt.vertical([Color(hex: 0xFF4081), amber], h - barHeight, h))
        }
        let colors = [Color(hex: 0xEC407A), Color(hex: 0x26C6DA), gold, Color(hex: 0xB388FF), Color(hex: 0x69F0AE)]
        for i in 0 ..< 18 {
            let speed = (50 + 40 * hash(i, 2)) * u
            let travel = h * 0.9
            let p = (hash(i, 3) * travel + t * speed).truncatingRemainder(dividingBy: travel)
            let y = h * 0.85 - p
            let x = hash(i, 4) * w + sin(t * 1.4 + CGFloat(i)) * 18 * u
            let fadeInOut = min(p / (travel * 0.15), 1) * min((travel - p) / (travel * 0.2), 1)
            musicNote(&c, CGPoint(x: x, y: y), (0.8 + 0.6 * hash(i, 5)) * u,
                      colors[i % colors.count].opacity(fadeInOut * dusk), double: i % 3 == 0)
        }
    }

    /// Halloween: a full moon rises, bats pour out of it across the sky, and pumpkins light along the bottom.
    private static func halloween(_ c: inout GraphicsContext, _ t: CGFloat, _ u: CGFloat, _ dusk: CGFloat, _ size: CGSize) {
        sky(&c, dusk, Color(hex: 0x24104A), Color(hex: 0x4A1A5E), Color(hex: 0x120612), size)
        stars(&c, t, u, dusk, 45, cream, 0.55, size)
        // Top left, clear of the turn-off pill at the top right.
        let moon = CGPoint(x: size.width * 0.22, y: size.height * 0.14)
        let r = 46 * u
        let rise = easeOut(min(max(t / 1.2, 0), 1))
        FestivalArt.circle(&c, FestivalArt.radial([paleGold.opacity(0.4 * rise), .clear], moon.x, moon.y, r * 2.6), r * 2.6, moon.x, moon.y)
        var risen = c
        risen.opacity = Double(rise)
        FestivalArt.circle(&risen, FestivalArt.linear([Color(hex: 0xFFFDE7), paleGold], moon.x - r, moon.y - r, moon.x + r, moon.y + r),
                           r, moon.x, moon.y)
        FestivalArt.circle(&c, gold.opacity(0.25 * rise), r * 0.2, moon.x - r * 0.3, moon.y + r * 0.2)
        FestivalArt.circle(&c, gold.opacity(0.2 * rise), r * 0.12, moon.x + r * 0.35, moon.y - r * 0.3)

        for i in 0 ..< 10 {
            let p = (t - 0.3 - CGFloat(i) * 0.22) / 2.6
            if p <= 0 || p >= 1 { continue }
            let angle = CGFloat.pi * (-0.3 + 0.55 * hash(i, 61))
            let reach = p * size.width * (0.7 + 0.4 * hash(i, 62))
            let at = CGPoint(x: moon.x + cos(angle) * reach,
                             y: moon.y - sin(angle) * reach * 0.35 + reach * 0.25 + sin(p * 9 + CGFloat(i)) * 10 * u)
            let span = (12 + 34 * p) * u * (0.7 + 0.6 * hash(i, 63))
            let fadeOut = 1 - min(max((p - 0.8) / 0.2, 0), 1)
            FestivalArt.bat(&c, at, span, sin(t * 16 + CGFloat(i) * 1.7), Color(hex: 0x07030C), alpha: dusk * fadeOut)
        }

        let n = 5
        for i in 0 ..< n {
            let lit = easeOut(min(max((t - 0.6 - CGFloat(i) * 0.18) / 0.5, 0), 1))
            let pr = (20 + 8 * hash(i, 64)) * u
            let x = size.width * (0.1 + 0.8 * CGFloat(i) / CGFloat(n - 1))
            let y = size.height - pr * 1.1 - 10 * u * hash(i, 65)
            FestivalArt.jackOLantern(&c, CGPoint(x: x, y: y), pr, lit * (0.8 + 0.2 * sin(t * 9 + CGFloat(i) * 2)), alpha: dusk)
        }
    }

    // MARK: Pieces

    private static func sky(_ c: inout GraphicsContext, _ alpha: CGFloat, _ top: Color, _ middle: Color, _ bottom: Color, _ size: CGSize) {
        var faded = c
        faded.opacity = Double(0.985 * alpha)
        faded.fill(Path(CGRect(origin: .zero, size: size)), with: FestivalArt.vertical([top, middle, bottom], 0, size.height))
    }

    private static func stars(_ c: inout GraphicsContext, _ t: CGFloat, _ u: CGFloat, _ alpha: CGFloat, _ count: Int, _ color: Color,
                              _ height: CGFloat, _ size: CGSize) {
        for i in 0 ..< count {
            let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 2.2 + CGFloat(i) * 0.9))
            FestivalArt.circle(&c, color.opacity(0.55 * twinkle * alpha), (1 + 1.6 * hash(i, 91)) * u,
                               hash(i, 92) * size.width, hash(i, 93) * size.height * height)
        }
    }

    /// A burst of `count` sparks thrown out from `at` at `start` seconds: they slow down, fall and
    /// fade over `life` seconds.
    private static func burst(_ c: inout GraphicsContext, _ t: CGFloat, _ start: CGFloat, _ at: CGPoint, _ colors: [Color],
                              _ count: Int, _ speed: CGFloat, _ life: CGFloat, _ gravity: CGFloat, _ u: CGFloat, seed: Int) {
        let age = t - start
        if age < 0 || age > life { return }
        let drag: CGFloat = 1.8
        let travel = (1 - exp(-drag * age)) / drag
        let fade = 1 - age / life
        if age < 0.25 { FestivalArt.circle(&c, Color.white.opacity(0.6 * (1 - age / 0.25)), 26 * u, at.x, at.y) }
        for i in 0 ..< count {
            let a = CGFloat(i) * 2 * .pi / CGFloat(count) + hash(i, seed) * 0.3
            let s = speed * (0.55 + 0.45 * hash(i, seed + 50))
            let x = at.x + cos(a) * s * travel
            let y = at.y + sin(a) * s * travel + 0.5 * gravity * age * age
            let color = colors[i % colors.count]
            FestivalArt.circle(&c, color.opacity(0.25 * fade), 7 * u, x, y)
            FestivalArt.circle(&c, color.opacity(fade), 2.3 * u, x, y)
        }
    }

    private static func confetti(_ c: inout GraphicsContext, _ t: CGFloat, _ u: CGFloat, _ alpha: CGFloat, _ count: Int, _ size: CGSize) {
        let colors = [Color(hex: 0xEC407A), gold, Color(hex: 0x26C6DA), Color(hex: 0x7E57C2), coral, Color(hex: 0x66BB6A)]
        for i in 0 ..< count {
            let speed = (60 + 60 * hash(i, 71)) * u
            let y = (hash(i, 72) * size.height + t * speed).truncatingRemainder(dividingBy: size.height * 1.05) - size.height * 0.03
            let x = hash(i, 73) * size.width + sin(t * 2 + CGFloat(i)) * 12 * u
            var turned = FestivalArt.rotated(c, t * (90 + 200 * hash(i, 74)) + CGFloat(i) * 40, x, y)
            turned.fill(Path(CGRect(x: x - 4 * u, y: y - 2 * u, width: 8 * u, height: 4 * u)),
                        with: .color(colors[i % colors.count].opacity(alpha)))
        }
    }

    /// A quaver or a beamed pair floating up the music scene; `at` is the first head's centre.
    private static func musicNote(_ c: inout GraphicsContext, _ at: CGPoint, _ s: CGFloat, _ color: Color, double: Bool) {
        func head(_ h: CGPoint) {
            var tilted = FestivalArt.rotated(c, -22, h.x, h.y)
            FestivalArt.oval(&tilted, .color(color), h.x - 7 * s, h.y - 5 * s, 14 * s, 10 * s)
            c.fill(Path(CGRect(x: h.x + 5 * s, y: h.y - 30 * s, width: 2.6 * s, height: 30 * s)), with: .color(color))
        }
        head(at)
        if double {
            let second = CGPoint(x: at.x + 22 * s, y: at.y - 5 * s)
            head(second)
            var beam = Path()
            beam.move(to: CGPoint(x: at.x + 5 * s, y: at.y - 30 * s))
            beam.addLine(to: CGPoint(x: second.x + 7.6 * s, y: second.y - 30 * s))
            beam.addLine(to: CGPoint(x: second.x + 7.6 * s, y: second.y - 23 * s))
            beam.addLine(to: CGPoint(x: at.x + 5 * s, y: at.y - 23 * s))
            beam.closeSubpath()
            c.fill(beam, with: .color(color))
        } else {
            var flag = Path()
            flag.move(to: CGPoint(x: at.x + 7.6 * s, y: at.y - 30 * s))
            flag.addQuadCurve(to: CGPoint(x: at.x + 15.6 * s, y: at.y - 14 * s), control: CGPoint(x: at.x + 17.6 * s, y: at.y - 26 * s))
            flag.addQuadCurve(to: CGPoint(x: at.x + 7.6 * s, y: at.y - 23 * s), control: CGPoint(x: at.x + 13.6 * s, y: at.y - 21 * s))
            flag.closeSubpath()
            c.fill(flag, with: .color(color))
        }
    }

    /// A clay lamp along the bottom of the Tihar and Diwali scene, centred at `base` (its rim).
    private static func bottomDiya(_ c: inout GraphicsContext, _ base: CGPoint, _ width: CGFloat, _ flicker: CGFloat, _ lit: CGFloat) {
        var bowl = Path()
        bowl.move(to: CGPoint(x: base.x - width / 2, y: base.y))
        bowl.addCurve(to: CGPoint(x: base.x + width / 2, y: base.y),
                      control1: CGPoint(x: base.x - width / 2.4, y: base.y + width * 0.42),
                      control2: CGPoint(x: base.x + width / 2.4, y: base.y + width * 0.42))
        bowl.addQuadCurve(to: CGPoint(x: base.x + width * 0.42, y: base.y - width * 0.02),
                          control: CGPoint(x: base.x + width * 0.62, y: base.y - width * 0.08))
        bowl.closeSubpath()
        c.fill(bowl, with: FestivalArt.vertical([clayLight, clay, clayDark], base.y - width * 0.1, base.y + width * 0.4))
        FestivalArt.oval(&c, .color(clayDark), base.x - width / 2, base.y - width * 0.06, width, width * 0.12)
        if lit <= 0 { return }
        let wobble = sin(flicker * 2 * .pi)
        let height = width * (0.55 + 0.06 * wobble) * lit
        let tip = CGPoint(x: base.x + width * 0.04 * wobble, y: base.y - width * 0.05 - height)
        FestivalArt.circle(&c, FestivalArt.radial([amber.opacity(0.55 * lit), .clear], base.x, base.y - height * 0.5, width * 0.9),
                           width * 0.9, base.x, base.y - height * 0.5)
        var flame = Path()
        flame.move(to: CGPoint(x: base.x, y: base.y - width * 0.04))
        flame.addCurve(to: tip, control1: CGPoint(x: base.x - width * 0.2, y: base.y - height * 0.35),
                       control2: CGPoint(x: tip.x - width * 0.05, y: tip.y + height * 0.3))
        flame.addCurve(to: CGPoint(x: base.x, y: base.y - width * 0.04), control1: CGPoint(x: tip.x + width * 0.05, y: tip.y + height * 0.3),
                       control2: CGPoint(x: base.x + width * 0.2, y: base.y - height * 0.35))
        flame.closeSubpath()
        var lamp = c
        lamp.opacity = Double(lit)
        lamp.fill(flame, with: FestivalArt.vertical([cream, Color(hex: 0xFFB300), coral], tip.y, base.y))
    }

    /// One rangoli petal, a pointed leaf from `base` pointing away from the centre.
    private static func petal(_ c: inout GraphicsContext, _ base: CGPoint, _ length: CGFloat, _ width: CGFloat, _ color: Color, _ u: CGFloat) {
        var leaf = Path()
        leaf.move(to: base)
        leaf.addCurve(to: CGPoint(x: base.x, y: base.y - length),
                      control1: CGPoint(x: base.x - width, y: base.y - length * 0.35),
                      control2: CGPoint(x: base.x - width * 0.4, y: base.y - length * 0.85))
        leaf.addCurve(to: base,
                      control1: CGPoint(x: base.x + width * 0.4, y: base.y - length * 0.85),
                      control2: CGPoint(x: base.x + width, y: base.y - length * 0.35))
        leaf.closeSubpath()
        c.fill(leaf, with: .color(color))
        // Android draws this outline 1.5 pixels wide, about half a point.
        c.stroke(leaf, with: .color(.white.opacity(0.25)), lineWidth: 0.5 * u)
    }

    /// A fixed pseudo-random number in 0…1 for item `i` and stream `k`: the same every frame.
    /// Worked in single precision exactly as Android does, so the stars, snow and sparks land in
    /// the same places on both.
    static func hash(_ i: Int, _ k: Int) -> CGFloat {
        let a: Float = Float(i) * 12.9898 + Float(k) * 78.233
        let x: Float = Float(sin(Double(a))) * 43758.547
        return CGFloat(x - x.rounded(.down))
    }

    static func easeOut(_ x: CGFloat) -> CGFloat { 1 - (1 - x) * (1 - x) * (1 - x) }

    /// Eases out past 1 and settles back, for things that pop in.
    static func backOut(_ x: CGFloat) -> CGFloat {
        let c: CGFloat = 1.7
        let y = x - 1
        return 1 + (c + 1) * y * y * y + c * y * y
    }
}
