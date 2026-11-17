import SwiftUI

/// Blazify Project (C) 2026
/// Licensed under GPL-3.0

/// The Blazify logo dressed for a festival, drawn live. Everything is laid out on the logo's own
/// 256-unit square, the one its picture fills, so a decoration never makes the logo bigger: it
/// only fills the empty space the logo already has around it. The same shapes, colours and
/// movements as the Android app, whose drawing uses the same 256 square.
struct FestivalLogoArt: View {
    let festival: Festival
    /// The white logo, for the dark celebration; Home's header keeps its coloured one.
    var white = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            // With Reduce Motion on, the logo holds still on a frame where everything shows.
            let t = reduceMotion ? 1.3 : timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: FestivalArt.loop)
            Canvas { context, size in
                FestivalArt.logo(&context, festival: festival, white: white, t: CGFloat(t), side: min(size.width, size.height))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The drawings, shared by the Home logo and the celebration.
enum FestivalArt {
    /// One loop of every logo animation, in seconds; each movement's period divides it.
    static let loop = 12.0

    static let gold = Color(hex: 0xFFC107)
    static let paleGold = Color(hex: 0xFFE082)
    private static let marigold = Color(hex: 0xFB8C00)
    private static let saffron = Color(hex: 0xFFA000)
    private static let makhamali = Color(hex: 0xC2185B)
    private static let batPurple = Color(hex: 0xAB47BC)

    /// The logo for `festival` in a `side`-point square at the context's origin.
    static func logo(_ context: inout GraphicsContext, festival: Festival, white: Bool, t: CGFloat, side: CGFloat) {
        var c = context
        c.scaleBy(x: side / 256, y: side / 256)
        switch festival {
        case .diwali:
            headphones(&c, white: white)
            garland(&c, t)
            diya(&c, t)
            sparkle(&c, 30, 92, 5, paleGold, t, 1.7)
            sparkle(&c, 228, 96, 5, gold, t, 0.4)
        case .halloween:
            headphones(&c, white: white)
            halloween(&c, t)
        case .christmas:
            image(&c, white: white)
            santaHat(&c, t)
        case .newYear:
            image(&c, white: white)
            fireworks(&c, t)
        case .musicDay:
            image(&c, white: white)
            musicNotes(&c, t)
        case .holi, .dashain, .lunarNewYear, .eidAlFitr, .eidAlAdha:
            // No days yet, so they never show; the plain logo, should one ever be forced.
            image(&c, white: white)
        }
    }

    // MARK: The logo itself

    private static func picture(white: Bool) -> Image {
        Image(bundleImage: white ? "blaze_logo_white" : "blaze_logo").interpolation(.high)
    }

    private static let square = CGRect(x: 0, y: 0, width: 256, height: 256)

    private static func image(_ c: inout GraphicsContext, white: Bool) {
        c.draw(picture(white: white), in: square)
    }

    /// The logo's parts, parsed once. They are traced on the 1024 square the 256 picture was
    /// made from, so a quarter of their size lands exactly on the picture.
    private static let parts: [Path] = [BlazeLogoShapes.band, BlazeLogoShapes.cupLeft, BlazeLogoShapes.cupRight].map {
        BlazeLogoShapes.path($0).applying(CGAffineTransform(scaleX: 0.25, y: 0.25))
    }

    /// The headphones without the flame, where a festival puts its own light. The picture is
    /// drawn through each part's outline in turn, so its own colours and edges are kept.
    private static func headphones(_ c: inout GraphicsContext, white: Bool) {
        let resolved = c.resolve(picture(white: white))
        for part in parts {
            var clipped = c
            clipped.clip(to: part)
            clipped.draw(resolved, in: square)
        }
    }

    // MARK: Helpers

    static func wave(_ t: CGFloat, _ period: CGFloat, _ phase: CGFloat = 0) -> CGFloat {
        sin(2 * .pi * (t + phase) / period)
    }

    /// 0…1 over `period`, starting `delay` seconds in.
    static func cycle(_ t: CGFloat, _ period: CGFloat, _ delay: CGFloat = 0) -> CGFloat {
        let x = ((t - delay) / period).truncatingRemainder(dividingBy: 1)
        return x < 0 ? x + 1 : x
    }

    /// A copy of the context turned `degrees` clockwise about a point.
    static func rotated(_ c: GraphicsContext, _ degrees: CGFloat, _ px: CGFloat, _ py: CGFloat) -> GraphicsContext {
        var r = c
        r.translateBy(x: px, y: py)
        r.rotate(by: .degrees(Double(degrees)))
        r.translateBy(x: -px, y: -py)
        return r
    }

    static func scaled(_ c: GraphicsContext, _ s: CGFloat, _ px: CGFloat, _ py: CGFloat) -> GraphicsContext {
        var r = c
        r.translateBy(x: px, y: py)
        r.scaleBy(x: s, y: s)
        r.translateBy(x: -px, y: -py)
        return r
    }

    static func circle(_ c: inout GraphicsContext, _ shading: GraphicsContext.Shading, _ r: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: shading)
    }

    static func circle(_ c: inout GraphicsContext, _ color: Color, _ r: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        circle(&c, .color(color), r, x, y)
    }

    static func oval(_ c: inout GraphicsContext, _ shading: GraphicsContext.Shading, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: shading)
    }

    static func line(_ c: inout GraphicsContext, _ color: Color, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
                     _ width: CGFloat, round: Bool = false) {
        var p = Path()
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
        c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: round ? .round : .butt))
    }

    static func radial(_ colors: [Color], _ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> GraphicsContext.Shading {
        .radialGradient(Gradient(colors: colors), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius)
    }

    static func vertical(_ stops: [Gradient.Stop], _ top: CGFloat, _ bottom: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))
    }

    static func vertical(_ colors: [Color], _ top: CGFloat, _ bottom: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))
    }

    static func linear(_ colors: [Color], _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: x0, y: y0), endPoint: CGPoint(x: x1, y: y1))
    }

    /// A four-pointed sparkle that grows and fades in turn.
    static func sparkle(_ c: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color,
                        _ t: CGFloat, _ phase: CGFloat) {
        let on = 0.5 + 0.5 * wave(t, 3, phase)
        let s = r * (0.6 + 0.5 * on)
        var star = Path()
        star.move(to: CGPoint(x: x, y: y - s))
        star.addQuadCurve(to: CGPoint(x: x + s, y: y), control: CGPoint(x: x + s * 0.18, y: y - s * 0.18))
        star.addQuadCurve(to: CGPoint(x: x, y: y + s), control: CGPoint(x: x + s * 0.18, y: y + s * 0.18))
        star.addQuadCurve(to: CGPoint(x: x - s, y: y), control: CGPoint(x: x - s * 0.18, y: y + s * 0.18))
        star.addQuadCurve(to: CGPoint(x: x, y: y - s), control: CGPoint(x: x - s * 0.18, y: y - s * 0.18))
        star.closeSubpath()
        c.fill(star, with: .color(color.opacity(0.25 + 0.75 * on)))
    }

    // MARK: Tihar and Diwali

    /// Marigold (sayapatri) and makhamali garland over the headband, swaying a little.
    private static func garland(_ context: inout GraphicsContext, _ t: CGFloat) {
        var c = rotated(context, 1.2 * wave(t, 6), 128, 50)
        for i in 0 ..< 11 {
            let a = (18 + CGFloat(i) * 14.4) * .pi / 180
            let x = 128 - 71 * cos(a)
            let y = 121 - 71 * sin(a)
            if i % 3 == 1 { flowerMakhamali(&c, x, y, 6.2) } else { flowerMarigold(&c, x, y, 9) }
        }
        flowerMarigold(&c, 52, 132, 7)
        flowerMakhamali(&c, 50, 146, 5)
        flowerMarigold(&c, 204, 132, 7)
        flowerMakhamali(&c, 206, 146, 5)
    }

    private static func flowerMarigold(_ c: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        for i in 0 ..< 12 {
            let a = CGFloat(i) * .pi / 6
            circle(&c, marigold, r * 0.38, x + cos(a) * r * 0.72, y + sin(a) * r * 0.72)
        }
        circle(&c, saffron, r * 0.78, x, y)
        circle(&c, gold, r * 0.5, x, y)
        circle(&c, paleGold, r * 0.22, x - r * 0.15, y - r * 0.15)
    }

    private static func flowerMakhamali(_ c: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        circle(&c, makhamali, r, x, y)
        circle(&c, Color(hex: 0xF48FB1).opacity(0.8), r * 0.35, x - r * 0.3, y - r * 0.3)
    }

    /// A clay diyo with a real oil-lamp flame on its wick, flickering, on a half-ring of rangoli.
    private static func diya(_ c: inout GraphicsContext, _ t: CGFloat) {
        let glow = 0.55 + 0.45 * (0.5 + 0.5 * wave(t, 3))
        oval(&c, radial([Color(hex: 0xFFB74D).opacity(0.55 * glow), .clear], 128, 124, 58), 70, 66, 116, 116)
        rangoliDots(&c)

        var bowl = Path()
        bowl.move(to: CGPoint(x: 87, y: 164))
        bowl.addCurve(to: CGPoint(x: 169, y: 164), control1: CGPoint(x: 90, y: 195), control2: CGPoint(x: 166, y: 195))
        bowl.addCurve(to: CGPoint(x: 87, y: 164), control1: CGPoint(x: 157, y: 159.5), control2: CGPoint(x: 99, y: 159.5))
        bowl.closeSubpath()
        c.fill(bowl, with: vertical([
            .init(color: Color(hex: 0xE07B45), location: 0),
            .init(color: Color(hex: 0xB9532A), location: 0.45),
            .init(color: Color(hex: 0x6E2A12), location: 1),
        ], 159, 190))
        var handle = Path()
        handle.move(to: CGPoint(x: 169, y: 164))
        handle.addQuadCurve(to: CGPoint(x: 175, y: 151), control: CGPoint(x: 178, y: 158))
        handle.addQuadCurve(to: CGPoint(x: 160, y: 162), control: CGPoint(x: 171, y: 160))
        handle.closeSubpath()
        c.fill(handle, with: .color(Color(hex: 0xB9532A)))
        oval(&c, .color(Color(hex: 0x5A2310)), 87, 158, 82, 12)
        oval(&c, .color(Color(hex: 0x8A3A18)), 90.5, 159.5, 75, 7)
        for (i, x) in [100.0, 110, 119, 128, 137, 146, 156].enumerated() {
            circle(&c, Color(hex: 0xFFD54F), 2.2, CGFloat(x), i == 0 || i == 6 ? 176 : 179)
        }
        var band = Path()
        band.move(to: CGPoint(x: 101, y: 172))
        band.addQuadCurve(to: CGPoint(x: 155, y: 172), control: CGPoint(x: 128, y: 181))
        c.stroke(band, with: .color(Color(hex: 0xE8894A).opacity(0.7)), lineWidth: 1.6)
        lampFlame(&c, t)
    }

    /// The flame of an oil lamp standing on its wick: an orange outer flame, a yellow heart, a
    /// white-hot core and a touch of blue at the root. It stretches, narrows and leans like a
    /// real one; every period divides the 12 s loop, so it never jumps.
    private static func lampFlame(_ c: inout GraphicsContext, _ t: CGFloat) {
        let base: CGFloat = 162
        let height = 62 * (1 + 0.06 * wave(t, 0.75) + 0.03 * wave(t, 0.4))
        let width = 13 * (1 - 0.05 * wave(t, 0.75, 0.2))
        let lean = 3.2 * wave(t, 1.2) + 1.4 * wave(t, 0.5)

        let haloX = 128 + lean * 0.4, haloY = base - height * 0.45
        circle(&c, radial([Color(hex: 0xFFE082).opacity(0.55), Color(hex: 0xFF9800).opacity(0.18), .clear], haloX, haloY, height * 0.62),
               height * 0.62, haloX, haloY)
        c.fill(flameShape(128, base, height, width, lean), with: vertical([
            .init(color: Color(hex: 0xFF6D00), location: 0),
            .init(color: Color(hex: 0xFF9100), location: 0.55),
            .init(color: Color(hex: 0xFFB300), location: 1),
        ], base - height, base))
        c.fill(flameShape(128, base - 1, height * 0.72, width * 0.68, lean * 0.7),
               with: vertical([Color(hex: 0xFFC107), Color(hex: 0xFFEE58)], base - height * 0.72, base))
        c.fill(flameShape(128, base - 2, height * 0.42, width * 0.4, lean * 0.4), with: .color(Color(hex: 0xFFFDE7)))
        oval(&c, .color(Color(hex: 0x64B5F6).opacity(0.55)), 124, base - 6, 8, 6)
        line(&c, Color(hex: 0x3E2723), 128, base - 3, 128.6, base + 2, 2.2, round: true)
    }

    /// A teardrop standing on (cx, base), `height` tall, its tip leaned sideways by `lean`.
    private static func flameShape(_ cx: CGFloat, _ base: CGFloat, _ height: CGFloat, _ width: CGFloat, _ lean: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: cx, y: base))
        p.addCurve(to: CGPoint(x: cx + lean, y: base - height),
                   control1: CGPoint(x: cx - width * 1.35, y: base),
                   control2: CGPoint(x: cx - width * 0.75 + lean * 0.4, y: base - height * 0.6))
        p.addCurve(to: CGPoint(x: cx, y: base),
                   control1: CGPoint(x: cx + width * 0.75 + lean * 0.4, y: base - height * 0.6),
                   control2: CGPoint(x: cx + width * 1.35, y: base))
        p.closeSubpath()
        return p
    }

    private static func rangoliDots(_ c: inout GraphicsContext) {
        let colors = [Color(hex: 0xE91E63), Color(hex: 0x26A69A), gold, Color(hex: 0x7E57C2)]
        for k in 0 ..< 3 {
            let r = 22 + CGFloat(k) * 9
            for i in 0 ... 8 {
                let a = CGFloat.pi + CGFloat(i) * .pi / 8
                circle(&c, colors[(i + k) % 4], 3.4 - CGFloat(k) * 0.6, 128 + cos(a) * r * 1.7, 206 + sin(a) * r * 0.5)
            }
        }
    }

    // MARK: Christmas

    /// A Santa hat worn on the headband: the fur brim follows the band's curve.
    private static func santaHat(_ c: inout GraphicsContext, _ t: CGFloat) {
        var hat = Path()
        hat.move(to: CGPoint(x: 94, y: 52))
        hat.addCurve(to: CGPoint(x: 160, y: 6), control1: CGPoint(x: 96, y: 20), control2: CGPoint(x: 128, y: 2))
        hat.addCurve(to: CGPoint(x: 210, y: 48), control1: CGPoint(x: 184, y: 9), control2: CGPoint(x: 202, y: 24))
        hat.addCurve(to: CGPoint(x: 212, y: 72), control1: CGPoint(x: 214, y: 58), control2: CGPoint(x: 214, y: 66))
        hat.addCurve(to: CGPoint(x: 182, y: 44), control1: CGPoint(x: 204, y: 60), control2: CGPoint(x: 194, y: 50))
        hat.addCurve(to: CGPoint(x: 162, y: 50), control1: CGPoint(x: 176, y: 46), control2: CGPoint(x: 170, y: 48))
        hat.closeSubpath()
        c.fill(hat, with: linear([Color(hex: 0xEF5350), Color(hex: 0xB71C1C)], 94, 2, 214, 72))
        var shine = Path()
        shine.move(to: CGPoint(x: 112, y: 38))
        shine.addCurve(to: CGPoint(x: 170, y: 16), control1: CGPoint(x: 124, y: 18), control2: CGPoint(x: 150, y: 12))
        c.stroke(shine, with: .color(Color(hex: 0xFF8A80).opacity(0.45)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        var fold = Path()
        fold.move(to: CGPoint(x: 182, y: 44))
        fold.addCurve(to: CGPoint(x: 212, y: 72), control1: CGPoint(x: 194, y: 50), control2: CGPoint(x: 204, y: 60))
        c.stroke(fold, with: .color(Color(hex: 0x8E1414).opacity(0.5)), lineWidth: 2.5)
        // The brim is an arc of the headband's own circle (centre 128,121), so it sits on it.
        // Angles grow clockwise on screen, so these short arcs run over the top.
        for (from, to, color, width) in [(-120, -60, Color(hex: 0xF5F5F5), 17), (-116, -64, .white, 9)]
            as [(Double, Double, Color, CGFloat)] {
            var brim = Path()
            brim.addArc(center: CGPoint(x: 128, y: 121), radius: 78,
                        startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
            c.stroke(brim, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }

        var pompom = rotated(c, 0.5 + 4.5 * wave(t, 3), 201.5, 66.5)
        circle(&pompom, Color(hex: 0xFAFAFA), 11.5, 213, 78)
        circle(&pompom, .white, 4.5, 209, 74)
        circle(&pompom, Color(hex: 0xE0E0E0), 3, 216, 82)
        falling(&c, t, 0) { snowflake(&$0, 36, 40, 9) }
        falling(&c, t, 1) { snowflake(&$0, 232, 150, 7) }
        falling(&c, t, 2) { snowflake(&$0, 24, 160, 6) }
    }

    private static func snowflake(_ c: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        for i in 0 ..< 3 {
            let a = CGFloat(i) * .pi / 3
            line(&c, Color(hex: 0x90CAF9), x - cos(a) * r, y - sin(a) * r, x + cos(a) * r, y + sin(a) * r, 2.4, round: true)
        }
    }

    /// Something drifting down and fading at both ends, every three seconds. Drawn as one layer,
    /// so where its strokes cross they fade together rather than doubling up.
    private static func falling(_ context: inout GraphicsContext, _ t: CGFloat, _ delay: CGFloat,
                                _ content: (inout GraphicsContext) -> Void) {
        let p = cycle(t, 3, delay)
        let alpha: CGFloat = p < 0.15 ? p / 0.15 : p > 0.85 ? (1 - p) / 0.15 : 1
        var c = context
        c.opacity = Double(alpha)
        c.drawLayer { layer in
            layer.translateBy(x: 0, y: -30 + 70 * p)
            content(&layer)
        }
    }

    // MARK: New Year

    private static func fireworks(_ c: inout GraphicsContext, _ t: CGFloat) {
        burst(&c, t, 70, 34, 24, gold, Color(hex: 0xFF7043), 0)
        burst(&c, t, 140, 18, 22, Color(hex: 0xEC407A), Color(hex: 0xFFD54F), 0.8)
        burst(&c, t, 204, 40, 22, Color(hex: 0x26C6DA), Color(hex: 0xB388FF), 1.6)
        let confetti: [(CGFloat, CGFloat, Color, CGFloat)] = [
            (30, 92, Color(hex: 0xEC407A), 20),
            (226, 96, gold, -30),
            (22, 140, Color(hex: 0x26C6DA), 45),
            (232, 150, Color(hex: 0x7E57C2), -15),
            (40, 190, Color(hex: 0xFF7043), 60),
            (218, 196, Color(hex: 0x66BB6A), -40),
        ]
        for (i, piece) in confetti.enumerated() {
            let (x, y, color, angle) = piece
            falling(&c, t, i % 2 == 0 ? 0 : 1.5) { layer in
                var turned = rotated(layer, angle, x, y)
                turned.fill(Path(roundedRect: CGRect(x: x, y: y, width: 9, height: 4.5), cornerRadius: 1.5), with: .color(color))
            }
        }
    }

    /// A firework that opens from its centre, holds, and fades, every 2.4 s.
    private static func burst(_ context: inout GraphicsContext, _ t: CGFloat, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat,
                              _ c1: Color, _ c2: Color, _ delay: CGFloat) {
        let p = cycle(t, 2.4, delay)
        let grow = p < 0.6 ? 0.15 + 0.85 * (p / 0.6) : 1 + 0.15 * ((p - 0.6) / 0.4)
        let alpha: CGFloat = p < 0.15 ? p / 0.15 : p < 0.6 ? 1 : 1 - (p - 0.6) / 0.4
        var c = scaled(context, grow, x, y)
        for i in 0 ..< 12 {
            let a = CGFloat(i) * .pi / 6
            let color = (i % 2 == 1 ? c2 : c1).opacity(alpha)
            line(&c, color, x + cos(a) * r * 0.35, y + sin(a) * r * 0.35, x + cos(a) * r, y + sin(a) * r, 3, round: true)
            circle(&c, color, 2.2, x + cos(a) * (r + 4), y + sin(a) * (r + 4))
        }
        circle(&c, Color(hex: 0xFFF8E1).opacity(alpha), 3, x, y)
    }

    // MARK: World Music Day

    private static func musicNotes(_ context: inout GraphicsContext, _ t: CGFloat) {
        func lift(_ phase: CGFloat) -> CGFloat { 3 - 8 * (0.5 + 0.5 * wave(t, 4, phase)) }
        for (x, y, s, hex, double, phase) in [(214.0, 64.0, 1.0, 0xEC407A, false, 0.0),
                                              (30, 82, 0.85, 0x26C6DA, true, 1.2),
                                              (222, 118, 0.7, 0x7E57C2, false, 2.4)] as [(CGFloat, CGFloat, CGFloat, UInt, Bool, CGFloat)] {
            var c = context
            c.translateBy(x: 0, y: lift(phase))
            note(&c, x, y, s, Color(hex: hex), double: double)
        }
        sparkle(&context, 196, 30, 7, gold, t, 0)
        sparkle(&context, 48, 40, 5, gold, t, 1.4)
    }

    /// A quaver or a pair of beamed quavers; (x, y) is the first head's centre.
    static func note(_ c: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ color: Color, double: Bool) {
        func head(_ cx: CGFloat, _ cy: CGFloat) {
            var tilted = rotated(c, -22, cx, cy)
            oval(&tilted, .color(color), cx - 7 * s, cy - 5.2 * s, 14 * s, 10.4 * s)
            c.fill(Path(CGRect(x: cx + 5.2 * s, y: cy - 30 * s, width: 2.6 * s, height: 30 * s)), with: .color(color))
        }
        head(x, y)
        if !double {
            var flag = Path()
            flag.move(to: CGPoint(x: x + 7.8 * s, y: y - 30 * s))
            flag.addQuadCurve(to: CGPoint(x: x + 15.8 * s, y: y - 14 * s), control: CGPoint(x: x + 17.8 * s, y: y - 26 * s))
            flag.addQuadCurve(to: CGPoint(x: x + 7.8 * s, y: y - 23 * s), control: CGPoint(x: x + 13.8 * s, y: y - 21 * s))
            flag.closeSubpath()
            c.fill(flag, with: .color(color))
        } else {
            let x2 = x + 22 * s, y2 = y - 5 * s
            head(x2, y2)
            var beam = Path()
            beam.move(to: CGPoint(x: x + 5.2 * s, y: y - 30 * s))
            beam.addLine(to: CGPoint(x: x2 + 7.8 * s, y: y2 - 30 * s))
            beam.addLine(to: CGPoint(x: x2 + 7.8 * s, y: y2 - 23 * s))
            beam.addLine(to: CGPoint(x: x + 5.2 * s, y: y - 23 * s))
            beam.closeSubpath()
            c.fill(beam, with: .color(color))
        }
    }

    // MARK: Halloween

    /// A jack-o'-lantern glowing where the flame sits, and bats flitting past a full moon.
    private static func halloween(_ c: inout GraphicsContext, _ t: CGFloat) {
        circle(&c, radial([paleGold.opacity(0.45), .clear], 50, 50, 40), 40, 50, 50)
        circle(&c, linear([Color(hex: 0xFFFDE7), paleGold], 28, 28, 72, 72), 22, 50, 50)
        circle(&c, Color(hex: 0xFFD54F).opacity(0.35), 4, 43, 55)
        circle(&c, Color(hex: 0xFFD54F).opacity(0.3), 2.6, 58, 44)
        bat(&c, CGPoint(x: 54 + 6 * wave(t, 6), y: 54 + 3 * wave(t, 3)), 30, wave(t, 0.5), Color(hex: 0x1A1020))
        bat(&c, CGPoint(x: 102 + 8 * wave(t, 4, 1), y: 24 + 4 * wave(t, 2)), 32, wave(t, 0.4, 0.1), batPurple)
        bat(&c, CGPoint(x: 212 + 6 * wave(t, 6, 2), y: 38 + 3 * wave(t, 3, 1)), 36, wave(t, 0.5, 0.2), batPurple)
        let glow = 0.8 + 0.12 * wave(t, 2) + 0.08 * wave(t, 0.75)
        jackOLantern(&c, CGPoint(x: 128, y: 156), 34, glow)
    }

    /// A bat seen from the front, `span` wide, its wings at `flap` (-1 down to 1 up). Shared with
    /// the Halloween celebration.
    static func bat(_ context: inout GraphicsContext, _ at: CGPoint, _ span: CGFloat, _ flap: CGFloat, _ color: Color,
                    alpha: CGFloat = 1) {
        let s = span
        let f = flap * s * 0.14
        var wing = Path()
        wing.move(to: CGPoint(x: s * 0.04, y: -s * 0.03))
        wing.addQuadCurve(to: CGPoint(x: s * 0.5, y: -s * 0.1 - f), control: CGPoint(x: s * 0.24, y: -s * 0.2 - f))
        wing.addQuadCurve(to: CGPoint(x: s * 0.38, y: s * 0.05 - f * 0.5), control: CGPoint(x: s * 0.44, y: -s * 0.02 - f * 0.6))
        wing.addQuadCurve(to: CGPoint(x: s * 0.24, y: s * 0.07 - f * 0.3), control: CGPoint(x: s * 0.32, y: -s * 0.01 - f * 0.4))
        wing.addQuadCurve(to: CGPoint(x: s * 0.04, y: s * 0.08), control: CGPoint(x: s * 0.17, y: s * 0.01 - f * 0.2))
        wing.closeSubpath()
        let shade = GraphicsContext.Shading.color(color.opacity(alpha))
        var c = context
        c.translateBy(x: at.x, y: at.y)
        c.fill(wing, with: shade)
        var mirrored = c
        mirrored.scaleBy(x: -1, y: 1)
        mirrored.fill(wing, with: shade)
        oval(&c, shade, -s * 0.065, -s * 0.09, s * 0.13, s * 0.2)
        var ears = Path()
        ears.move(to: CGPoint(x: -s * 0.06, y: -s * 0.06))
        ears.addLine(to: CGPoint(x: -s * 0.05, y: -s * 0.15))
        ears.addLine(to: CGPoint(x: -s * 0.01, y: -s * 0.08))
        ears.move(to: CGPoint(x: s * 0.06, y: -s * 0.06))
        ears.addLine(to: CGPoint(x: s * 0.05, y: -s * 0.15))
        ears.addLine(to: CGPoint(x: s * 0.01, y: -s * 0.08))
        c.fill(ears, with: shade)
    }

    /// A carved pumpkin `r` half-wide, lit from inside at `glow` (0 dark to 1 bright). Shared with
    /// the Halloween celebration.
    static func jackOLantern(_ c: inout GraphicsContext, _ centre: CGPoint, _ r: CGFloat, _ glow: CGFloat, alpha: CGFloat = 1) {
        let g = min(max(glow, 0), 1)
        circle(&c, radial([Color(hex: 0xFF9800).opacity(0.5 * g * alpha), .clear], centre.x, centre.y, r * 1.9), r * 1.9, centre.x, centre.y)
        let h = r * 1.7
        let top = centre.y - h / 2
        func lobe(_ width: CGFloat, _ light: UInt, _ dark: UInt) {
            var faded = c
            faded.opacity = Double(alpha)
            oval(&faded, vertical([Color(hex: light), Color(hex: 0xF57C00), Color(hex: dark)], top, top + h),
                 centre.x - width / 2, top, width, h)
        }
        lobe(r * 2, 0xFFA726, 0xBF360C)
        lobe(r * 1.3, 0xFFB74D, 0xD84315)
        lobe(r * 0.62, 0xFFCC80, 0xE65100)
        c.fill(Path(roundedRect: CGRect(x: centre.x - r * 0.1, y: top - r * 0.26, width: r * 0.2, height: r * 0.34),
                    cornerRadius: r * 0.06),
               with: .color(Color(hex: 0x5D4037).opacity(alpha)))
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: centre.x + x * r, y: centre.y + y * r) }
        // Eyes, nose and a toothy grin.
        var face = Path()
        face.move(to: at(-0.56, -0.06)); face.addLine(to: at(-0.18, -0.06)); face.addLine(to: at(-0.34, -0.4)); face.closeSubpath()
        face.move(to: at(0.56, -0.06)); face.addLine(to: at(0.18, -0.06)); face.addLine(to: at(0.34, -0.4)); face.closeSubpath()
        face.move(to: at(-0.09, 0.1)); face.addLine(to: at(0.09, 0.1)); face.addLine(to: at(0, -0.04)); face.closeSubpath()
        face.move(to: at(-0.6, 0.2))
        for (x, y) in [(-0.36, 0.3), (-0.26, 0.2), (-0.12, 0.32), (0, 0.22), (0.12, 0.32), (0.26, 0.2), (0.36, 0.3), (0.6, 0.2)]
            as [(CGFloat, CGFloat)] {
            face.addLine(to: at(x, y))
        }
        face.addQuadCurve(to: at(-0.6, 0.2), control: at(0, 0.78))
        face.closeSubpath()
        c.fill(face, with: .color(Color(hex: 0x3E1600).opacity(alpha)))
        var lit = c
        lit.opacity = Double(alpha * (0.35 + 0.65 * g))
        lit.fill(face, with: radial([Color(hex: 0xFFFDE7), Color(hex: 0xFFEB3B), Color(hex: 0xFFB300)], centre.x, centre.y, r * 0.9))
    }
}
