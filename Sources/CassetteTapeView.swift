import SwiftUI

/// Retro palette — deliberately NOT themed.
enum Retro {
    static let shellTop = Color(hex: 0x5A4B3D)
    static let shellMid = Color(hex: 0x3B3128)
    static let shellBottom = Color(hex: 0x262019)
    static let labelCream = Color(hex: 0xF2E7D0)
    static let labelCreamDark = Color(hex: 0xE4D6BC)
    static let labelBorder = Color(hex: 0xC9B999)
    static let windowDark = Color(hex: 0x241D15)
    static let spoolDark = Color(hex: 0x14100B)
    static let hubCream = Color(hex: 0xEFE6D2)
    static let inkBrown = Color(hex: 0x3A2F24)

    static let cream = Color(hex: 0xF2E7D0)
    static let ink = Color(hex: 0x3A2F24)
    static let darkKey = Color(hex: 0x2A241E)
}

/// A drawn cassette that moves like a real tape. The tape runs past the heads at one steady
/// speed, so each reel turns at that speed over the radius of the tape wound on it: the nearly
/// empty reel spins fast and the full one slowly, and they trade places through the song. Each
/// pack's size follows the tape on it (its area grows with the tape), a jump in the song winds
/// the tape there at speed as fast-forward did, and paused, the reels stop where they are.
struct CassetteTapeView: View {
    let isPlaying: Bool
    let progress: Double
    let accent: Color
    let artURL: URL?

    /// Where each reel has turned to, kept between frames.
    @State private var reels = ReelMotion()

    var body: some View {
        GeometryReader { geo in
            let bw = geo.size.width
            let bh = geo.size.height

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
                let angles = reels.step(at: timeline.date, tape: progress, playing: isPlaying)

                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in drawBase(ctx, size) }

                    // Album art printed faintly across the whole label.
                    RemoteImage(url: artURL) { Color.clear }
                        .frame(width: bw * 0.83, height: bh * 0.545)
                        .clipShape(RoundedRectangle(cornerRadius: bw * 0.02))
                        .opacity(0.22)
                        .offset(x: bw * 0.075, y: bh * 0.075)

                    Canvas { ctx, size in
                        drawDetails(ctx, size, tape: progress, left: angles.left, right: angles.right, accent: accent)
                    }

                    // Crisp little art chip on the label.
                    RemoteImage(url: artURL) { Color.black.opacity(0.2) }
                        .frame(width: bw * 0.055, height: bh * 0.085)
                        .clipShape(RoundedRectangle(cornerRadius: bw * 0.008))
                        .overlay(
                            RoundedRectangle(cornerRadius: bw * 0.008)
                                .stroke(Retro.inkBrown.opacity(0.6), lineWidth: 1),
                        )
                        .offset(x: bw * 0.10, y: bh * 0.10)

                    Text("A")
                        .font(.system(size: bw * 0.045, weight: .black))
                        .foregroundStyle(Retro.inkBrown)
                        .offset(x: bw * 0.182, y: bh * 0.095)

                    Text("60")
                        .font(.system(size: bw * 0.052, weight: .black))
                        .foregroundStyle(.white)
                        .offset(x: bw * 0.82, y: bh * 0.465)
                }
            }
        }
        .aspectRatio(1.55, contentMode: .fit)
        // Coming back from a pause, the clock picks up from now rather than counting the pause.
        .onChange(of: isPlaying) { reels.restartClock() }
    }

    // MARK: Base (shell, screws, label backing)

    private func drawBase(_ ctx: GraphicsContext, _ size: CGSize) {
        let s = size.width, t = size.height

        func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }

        // Three stacked drop shadows (wide/soft → tight/dark).
        ctx.fill(rr(s * 0.05, t * 0.10, s * 0.97, t * 0.93, s * 0.06), with: .color(.black.opacity(0.08)))
        ctx.fill(rr(s * 0.035, t * 0.075, s * 0.965, t * 0.925, s * 0.055), with: .color(.black.opacity(0.14)))
        ctx.fill(rr(s * 0.022, t * 0.048, s * 0.96, t * 0.93, s * 0.05), with: .color(.black.opacity(0.24)))

        // Shell.
        let shell = rr(s * 0.005, 0, s * 0.97, t * 0.955, s * 0.045)
        ctx.fill(shell, with: .linearGradient(
            Gradient(colors: [Retro.shellTop, Retro.shellMid, Retro.shellBottom]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: t * 0.955)))

        // Inner bevel + outer hairline.
        ctx.stroke(rr(s * 0.005 + s * 0.012, t * 0.02, s * 0.97 - s * 0.024, t * 0.955 - t * 0.04, s * 0.035),
                   with: .color(.black.opacity(0.35)), lineWidth: s * 0.003)
        ctx.stroke(shell, with: .color(.white.opacity(0.10)), lineWidth: s * 0.0025)

        // Top catch-light / bottom shade.
        var top = Path(); top.move(to: CGPoint(x: s * 0.06, y: t * 0.018)); top.addLine(to: CGPoint(x: s * 0.92, y: t * 0.018))
        ctx.stroke(top, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: t * 0.012, lineCap: .round))
        var bot = Path(); bot.move(to: CGPoint(x: s * 0.06, y: t * 0.935)); bot.addLine(to: CGPoint(x: s * 0.92, y: t * 0.935))
        ctx.stroke(bot, with: .color(.black.opacity(0.30)), style: StrokeStyle(lineWidth: t * 0.014, lineCap: .round))

        // Four corner screws.
        for (fx, fy) in [(0.045, 0.07), (0.935, 0.07), (0.045, 0.87), (0.935, 0.87)] {
            let c = CGPoint(x: s * fx, y: t * fy)
            let r = s * 0.016
            let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.fill(circle, with: .color(Color(hex: 0x1C1712)))
            ctx.stroke(circle, with: .color(.white.opacity(0.20)), lineWidth: s * 0.003)
            var slot = Path()
            slot.move(to: CGPoint(x: c.x - s * 0.008, y: c.y))
            slot.addLine(to: CGPoint(x: c.x + s * 0.008, y: c.y))
            ctx.stroke(slot, with: .color(Color(hex: 0x54463A)), lineWidth: s * 0.004)
        }

        // Cream label backing.
        ctx.fill(rr(s * 0.075, t * 0.075, s * 0.83, t * 0.545, s * 0.02),
                 with: .linearGradient(Gradient(colors: [Retro.labelCream, Retro.labelCreamDark]),
                                       startPoint: CGPoint(x: 0, y: t * 0.075),
                                       endPoint: CGPoint(x: 0, y: t * 0.62)))
    }

    // MARK: Details (label print, window, reels, trapezoid)

    private func drawDetails(_ ctx: GraphicsContext, _ size: CGSize,
                             tape: Double, left leftAngle: Double, right rightAngle: Double, accent: Color) {
        let s = size.width, t = size.height
        let p = CGFloat(min(max(tape, 0), 1))

        func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }

        // Label frame + "A" badge box.
        ctx.stroke(rr(s * 0.075, t * 0.075, s * 0.83, t * 0.545, s * 0.02),
                   with: .color(Retro.labelBorder), lineWidth: s * 0.004)
        ctx.stroke(rr(s * 0.17, t * 0.10, s * 0.055, t * 0.085, s * 0.008),
                   with: .color(Retro.inkBrown), lineWidth: s * 0.0045)

        // Accent stripe (dynamic album colour) + print lines + echo stripe.
        ctx.fill(Path(CGRect(x: s * 0.075, y: t * 0.455, width: s * 0.83, height: t * 0.105)),
                 with: .color(accent))
        for i in 1...3 {
            let ly = t * (0.455 + 0.105 * CGFloat(i) / 4.0)
            var line = Path()
            line.move(to: CGPoint(x: s * 0.075, y: ly)); line.addLine(to: CGPoint(x: s * 0.905, y: ly))
            ctx.stroke(line, with: .color(.black.opacity(0.10)), lineWidth: t * 0.006)
        }
        ctx.fill(Path(CGRect(x: s * 0.075, y: t * 0.575, width: s * 0.83, height: t * 0.022)),
                 with: .color(accent.opacity(0.55)))

        // Window.
        let winRect = CGRect(x: s * 0.285, y: t * 0.155, width: s * 0.43, height: t * 0.27)
        let winRadius = s * 0.02
        let window = Path(roundedRect: winRect, cornerRadius: winRadius)
        ctx.fill(window, with: .color(Retro.windowDark))
        ctx.stroke(window, with: .color(.black.opacity(0.55)), lineWidth: s * 0.008)

        // Reels — spool radius IS the progress indicator.
        let reelY = t * 0.29
        let leftC = CGPoint(x: s * 0.385, y: reelY)
        let rightC = CGPoint(x: s * 0.615, y: reelY)
        // Each pack holds its share of the tape: the left gives it up, the right takes it on.
        let hub = s * ReelMotion.hubShare
        let leftSpool = hub * CGFloat(ReelMotion.packRadius(Double(1 - p)))
        let rightSpool = hub * CGFloat(ReelMotion.packRadius(Double(p)))

        var clipped = ctx
        clipped.clip(to: window)

        // Tape bridge + sheen along the window bottom.
        var bridge = Path()
        bridge.move(to: CGPoint(x: leftC.x, y: winRect.maxY - t * 0.02))
        bridge.addLine(to: CGPoint(x: rightC.x, y: winRect.maxY - t * 0.02))
        clipped.stroke(bridge, with: .color(Retro.spoolDark), lineWidth: t * 0.028)
        var sheen = Path()
        sheen.move(to: CGPoint(x: leftC.x, y: winRect.maxY - t * 0.026))
        sheen.addLine(to: CGPoint(x: rightC.x, y: winRect.maxY - t * 0.026))
        clipped.stroke(sheen, with: .color(.white.opacity(0.10)), lineWidth: t * 0.006)

        for (center, spool, rotation) in [(leftC, leftSpool, leftAngle), (rightC, rightSpool, rightAngle)] {
            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
            clipped.fill(circle(spool), with: .color(Retro.spoolDark))
            clipped.stroke(circle(spool * 0.85), with: .color(.white.opacity(0.05)), lineWidth: 1.2)
            clipped.stroke(circle(spool * 0.65), with: .color(.white.opacity(0.05)), lineWidth: 1.2)

            // Rotating 6-tooth hub.
            var hub = clipped
            hub.translateBy(x: center.x, y: center.y)
            hub.rotate(by: .degrees(rotation))
            hub.translateBy(x: -center.x, y: -center.y)
            hub.stroke(circle(s * 0.042), with: .color(Retro.hubCream), lineWidth: s * 0.013)
            for i in 0..<6 {
                let a = Double(i) * 60 * .pi / 180
                let dir = CGPoint(x: CGFloat(cos(a)), y: CGFloat(sin(a)))
                var tooth = Path()
                tooth.move(to: CGPoint(x: center.x + dir.x * s * 0.016, y: center.y + dir.y * s * 0.016))
                tooth.addLine(to: CGPoint(x: center.x + dir.x * s * 0.040, y: center.y + dir.y * s * 0.040))
                hub.stroke(tooth, with: .color(Retro.hubCream),
                           style: StrokeStyle(lineWidth: s * 0.011, lineCap: .round))
            }

            clipped.fill(circle(s * 0.012), with: .color(Retro.windowDark))
        }

        // Glass gloss.
        clipped.fill(window, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.09), .clear, .clear]),
            startPoint: CGPoint(x: winRect.minX, y: winRect.minY),
            endPoint: CGPoint(x: winRect.minX + winRect.width * 0.8, y: winRect.maxY)))

        // Bottom trapezoid + capstan holes.
        var trap = Path()
        trap.move(to: CGPoint(x: s * 0.30, y: t * 0.945))
        trap.addLine(to: CGPoint(x: s * 0.35, y: t * 0.755))
        trap.addLine(to: CGPoint(x: s * 0.65, y: t * 0.755))
        trap.addLine(to: CGPoint(x: s * 0.70, y: t * 0.945))
        ctx.stroke(trap, with: .color(Color(hex: 0x6B5B49).opacity(0.65)), lineWidth: s * 0.006)

        for hx in [0.415, 0.585] {
            let c = CGPoint(x: s * hx, y: t * 0.85), r = s * 0.016
            let hole = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.fill(hole, with: .color(Color(hex: 0x17120D)))
            ctx.stroke(hole, with: .color(.white.opacity(0.18)), lineWidth: s * 0.003)
        }
        for hx in [0.375, 0.625] {
            let c = CGPoint(x: s * hx, y: t * 0.79), r = s * 0.009
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(hex: 0x17120D)))
        }

        // Whole-shell plastic sheen.
        ctx.fill(rr(s * 0.005, 0, s * 0.97, t * 0.955, s * 0.045), with: .linearGradient(
            Gradient(colors: [.white.opacity(0.07), .clear, .clear]),
            startPoint: .zero, endPoint: CGPoint(x: s * 0.9, y: t)))
    }
}

/// Where the two reels have turned to, kept between frames, and how they move: the tape passes
/// at one steady speed, so each turns by the tape that ran over its own radius.
final class ReelMotion {
    /// The hub's radius as a share of the cassette's width.
    static let hubShare: CGFloat = 0.059
    /// A full pack's radius in hub radii.
    static let fullPack = 1.95
    /// Tape speed past the heads while playing, in hub radii a second: an empty hub turns about
    /// once a second.
    static let playSpeed = 6.3
    /// The whole tape in hub radii: a jump across all of it winds the small reel round about 25 times.
    static let windLength = 160.0

    /// A pack's radius in hub radii, holding [share] of the tape: its area grows with the tape on it.
    static func packRadius(_ share: Double) -> Double {
        (1 + (fullPack * fullPack - 1) * min(max(share, 0), 1)).squareRoot()
    }

    private(set) var left = 0.0
    private(set) var right = 0.0
    private var lastTape: Double?
    private var lastTime: Date?

    func restartClock() { lastTime = nil }

    /// Moves the reels on to [date] and gives their angles in degrees.
    func step(at date: Date, tape: Double, playing: Bool) -> (left: Double, right: Double) {
        let tp = min(max(tape, 0), 1)
        let dt = lastTime.map { min(max(date.timeIntervalSince($0), 0), 0.1) } ?? 0
        var moved = (tp - (lastTape ?? tp)) * Self.windLength
        if playing { moved += Self.playSpeed * dt }
        lastTape = tp
        lastTime = date
        // Both reels turn the same way, anticlockwise from the front, as the tape runs left to right.
        let degrees = 180 / Double.pi
        left = (left - moved / Self.packRadius(1 - tp) * degrees).truncatingRemainder(dividingBy: 360)
        right = (right - moved / Self.packRadius(tp) * degrees).truncatingRemainder(dividingBy: 360)
        return (left, right)
    }
}
