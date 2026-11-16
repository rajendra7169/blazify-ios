import SwiftUI

/// The card the app asks things with: a new version is ready, or would you star Blazify. One
/// compact card, an object drawn in 3D breaking out of its top edge, a title, two lines and two
/// buttons, the same as on Android. The objects are drawn here rather than shipped as pictures,
/// so they stay sharp at any size and follow light and dark.
struct BlazePromptCard: View {
    enum Art { case rocket, star }

    let art: Art
    let title: String
    let message: String
    let primary: String
    let secondary: String
    var onPrimary: () -> Void
    var onSecondary: () -> Void
    /// Tapping outside the card: put off, not answered.
    var onDismiss: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        GeometryReader { space in
            // Short screens, a phone on its side or large text: a smaller picture and sky.
            let compact = space.size.height < 560
            let overflow: CGFloat = compact ? 32 : 46
            let artSide: CGFloat = compact ? 88 : 132
            let sky: CGFloat = compact ? 58 : 84
            ZStack {
                Color.black.opacity(shown ? 0.45 : 0)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                ScrollView(.vertical, showsIndicators: false) {
                    card(overflow: overflow, artSide: artSide, sky: sky)
                        .frame(maxWidth: 300)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(minHeight: space.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.94)
                .offset(y: shown ? 0 : 28)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.72)) { shown = true }
        }
    }

    private func card(overflow: CGFloat, artSide: CGFloat, sky: CGFloat) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                    let time = reduceMotion ? 0.15 : Self.cycle(timeline.date)
                    Canvas { context, size in
                        PromptArt.sky(&context, size: size, time: time, dark: scheme == .dark)
                    }
                }
                .frame(height: sky)
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        pill(secondary, primary: false, action: onSecondary)
                        pill(primary, primary: true, action: onPrimary)
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .background(palette.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .padding(.top, overflow)

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let time = reduceMotion ? 0.15 : Self.cycle(timeline.date)
                Canvas { context, size in
                    switch art {
                    case .rocket: PromptArt.rocket(&context, size: size, time: time)
                    case .star: PromptArt.star(&context, size: size, time: time)
                    }
                }
            }
            .frame(width: artSide, height: artSide)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func pill(_ label: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: primary ? .bold : .medium))
                .foregroundStyle(primary ? Color(red: 0.10, green: 0.055, blue: 0) : palette.onSurface)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 46)
                .padding(.horizontal, 6)
                .background {
                    if primary {
                        LinearGradient(colors: [Blaze.amber, PromptArt.coral], startPoint: .leading, endPoint: .trailing)
                    } else {
                        palette.onSurface.opacity(0.08)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Everything that moves runs on one slow clock: a full turn every six seconds.
    static func cycle(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
    }
}

/// The drawings. Each works in a 100 × 100 space scaled to its canvas.
enum PromptArt {
    static let coral = Color(red: 1, green: 0.439, blue: 0.263)
    private static let amber = Blaze.amber

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        func channel(_ shift: UInt32) -> Double {
            let x = Double(a >> shift & 0xff), y = Double(b >> shift & 0xff)
            return (x + (y - x) * t) / 255
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }

    // MARK: Sky

    /// A warm glow fading down the card's top, with faint notes floating in it.
    static func sky(_ context: inout GraphicsContext, size: CGSize, time: Double, dark: Bool) {
        let glow = amber.opacity(dark ? 0.20 : 0.16)
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [glow, .clear]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let ink: Color = dark ? .white : amber
        for (x, y, phase) in [(0.12, 0.62, 0.0), (0.88, 0.42, 0.3), (0.22, 0.3, 0.55), (0.78, 0.78, 0.8)] {
            let wave = sin((time + phase) * 2 * .pi * 2)
            note(&context, at: CGPoint(x: size.width * x, y: size.height * y - wave * 3), height: 11,
                 color: ink.opacity(0.13 + 0.05 * wave))
        }
    }

    // MARK: Rocket

    /// A glossy rocket climbing to the right, the Blazify logo in its porthole, and smoke and
    /// notes coming out of its nozzle.
    static func rocket(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        let u = min(size.width, size.height) / 100
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * u, y: y * u) }
        var c = context
        let bob = sin(time * 2 * .pi * 2) * 1.1
        c.translateBy(x: 50 * u, y: 52 * u)
        c.rotate(by: .degrees(38))
        c.translateBy(x: -50 * u, y: -52 * u + (bob - 5) * u)

        // Smoke: a cloud centred on the rocket's line under the nozzle, lit from the top left.
        for (i, (x, y, r)) in [(50.0, 84.0, 6.5), (44.5, 89.5, 6.0), (55.5, 89.5, 6.0), (50.0, 95.0, 6.5)].enumerated() {
            let breathe = 1 + 0.08 * sin(time * 2 * .pi * 2 + Double(i))
            let radius = r * breathe * u
            c.fill(Path(ellipseIn: CGRect(x: x * u - radius, y: y * u - radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(Gradient(colors: [.white, rgb(0xEDE6DF), rgb(0xC9BEB4)]),
                                         center: p(x - r * 0.35, y - r * 0.4), startRadius: 0, endRadius: r * 1.4 * u))
        }
        // Small puffs leaving the nozzle, spreading evenly to both sides as they fade.
        for i in 0 ..< 6 {
            let t = (time * 3 + Double(i) / 6).truncatingRemainder(dividingBy: 1)
            let side: Double = i % 2 == 0 ? -1 : 1
            let centre = p(50 + side * 7 * t, 80 + 24 * t)
            let radius = (2.4 + 4.2 * t) * u
            var puff = c
            puff.opacity = (1 - t) * 0.9
            puff.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                      with: .radialGradient(Gradient(colors: [.white, rgb(0xE3DAD1)]),
                                            center: CGPoint(x: centre.x - radius * 0.3, y: centre.y - radius * 0.35),
                                            startRadius: 0, endRadius: radius * 1.3))
        }
        // Two notes tumbling out with the smoke, one each side.
        for i in 0 ... 1 {
            let t = (time * 2 + Double(i) / 2).truncatingRemainder(dividingBy: 1)
            let side: Double = i == 0 ? -1 : 1
            note(&c, at: p(50 + side * (6 + 6 * t), 86 + 14 * t), height: 8.5 * u, color: amber.opacity((1 - t) * 0.95))
        }
        // Fins behind the body.
        var left = Path()
        left.move(to: p(37, 50))
        left.addCurve(to: p(27, 80), control1: p(26, 56), control2: p(24, 70))
        left.addCurve(to: p(39, 71), control1: p(31, 75), control2: p(35, 72))
        left.closeSubpath()
        c.fill(left, with: .linearGradient(Gradient(colors: [rgb(0xFF8A65), coral, rgb(0xBF360C)]), startPoint: p(30, 55), endPoint: p(40, 82)))
        var right = Path()
        right.move(to: p(63, 50))
        right.addCurve(to: p(73, 80), control1: p(74, 56), control2: p(76, 70))
        right.addCurve(to: p(61, 71), control1: p(69, 75), control2: p(65, 72))
        right.closeSubpath()
        c.fill(right, with: .linearGradient(Gradient(colors: [rgb(0xFF8A65), coral, rgb(0x8D2A0A)]), startPoint: p(62, 55), endPoint: p(74, 82)))
        // Nozzle.
        var nozzle = Path()
        nozzle.move(to: p(43, 72)); nozzle.addLine(to: p(57, 72)); nozzle.addLine(to: p(55, 79)); nozzle.addLine(to: p(45, 79))
        nozzle.closeSubpath()
        c.fill(nozzle, with: .linearGradient(Gradient(colors: [rgb(0x6D6259), rgb(0xB7ACA2), rgb(0x4E453E)]), startPoint: p(43, 75), endPoint: p(57, 75)))
        // Body: a rounded shell, shaded like a cylinder lit from the left.
        var body = Path()
        body.move(to: p(50, 8))
        body.addCurve(to: p(64, 52), control1: p(61, 16), control2: p(66, 32))
        body.addCurve(to: p(58, 74), control1: p(63, 62), control2: p(61, 70))
        body.addLine(to: p(42, 74))
        body.addCurve(to: p(36, 52), control1: p(39, 70), control2: p(37, 62))
        body.addCurve(to: p(50, 8), control1: p(34, 32), control2: p(39, 16))
        body.closeSubpath()
        c.fill(body, with: .linearGradient(Gradient(stops: [
            .init(color: rgb(0xB3A79C), location: 0), .init(color: .white, location: 0.3),
            .init(color: rgb(0xF1EBE5), location: 0.62), .init(color: rgb(0x94877B), location: 1),
        ]), startPoint: p(36, 40), endPoint: p(64, 40)))
        var inside = c
        inside.clip(to: body)
        // Amber nose cone, the waist band and a shine down the lit side.
        inside.fill(Path(CGRect(x: 30 * u, y: 0, width: 40 * u, height: 25 * u)), with: .linearGradient(Gradient(stops: [
            .init(color: rgb(0xD84315), location: 0), .init(color: rgb(0xFFCC80), location: 0.32),
            .init(color: amber, location: 0.6), .init(color: rgb(0xBF360C), location: 1),
        ]), startPoint: p(36, 10), endPoint: p(64, 10)))
        inside.fill(Path(CGRect(x: 30 * u, y: 63 * u, width: 40 * u, height: 4 * u)), with: .linearGradient(Gradient(stops: [
            .init(color: rgb(0xBF360C), location: 0), .init(color: rgb(0xFFB74D), location: 0.35), .init(color: rgb(0x8D2A0A), location: 1),
        ]), startPoint: p(36, 65), endPoint: p(64, 65)))
        inside.fill(Path(CGRect(x: 40 * u, y: 14 * u, width: 6 * u, height: 54 * u)), with: .linearGradient(Gradient(colors: [
            .white.opacity(0), .white.opacity(0.75), .white.opacity(0),
        ]), startPoint: p(40, 40), endPoint: p(46, 40)))
        // Porthole: a gold rim around dark glass, the Blazify logo behind it in amber.
        let port = p(50, 41)
        let rim = 11 * u, glass = 8.6 * u
        c.fill(Path(ellipseIn: CGRect(x: port.x - rim, y: port.y - rim, width: rim * 2, height: rim * 2)),
               with: .linearGradient(Gradient(colors: [rgb(0xFFE082), rgb(0xFFA000), rgb(0x8D5A00)]),
                                     startPoint: CGPoint(x: port.x - rim, y: port.y - rim), endPoint: CGPoint(x: port.x + rim, y: port.y + rim)))
        c.fill(Path(ellipseIn: CGRect(x: port.x - glass, y: port.y - glass, width: glass * 2, height: glass * 2)),
               with: .radialGradient(Gradient(colors: [rgb(0x4E342E), rgb(0x1A0E00)]),
                                     center: CGPoint(x: port.x - 2 * u, y: port.y - 2 * u), startRadius: 0, endRadius: 10.5 * u))
        var logo = c
        let side = 14 * u
        logo.translateBy(x: port.x - side / 2, y: port.y - side / 2)
        logo.scaleBy(x: side / BlazeLogoShapes.viewSize, y: side / BlazeLogoShapes.viewSize)
        logo.translateBy(x: -BlazeLogoShapes.viewLeft, y: -BlazeLogoShapes.viewTop)
        for part in [BlazeLogoShapes.band, BlazeLogoShapes.cupLeft, BlazeLogoShapes.cupRight, BlazeLogoShapes.flame] {
            logo.fill(BlazeLogoShapes.path(part), with: .color(amber))
        }
        var shine = Path()
        shine.addArc(center: port, radius: 7.4 * u, startAngle: .degrees(195), endAngle: .degrees(250), clockwise: false)
        c.stroke(shine, with: .color(.white.opacity(0.55)), lineWidth: 1.1 * u)
    }

    // MARK: Star

    /// A faceted gold star breathing in and out a little, a note engraved in it, a glint at a
    /// tip, notes above it and GitHub marks floating beside it.
    static func star(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        let u = min(size.width, size.height) / 100
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * u, y: y * u) }
        let beat = sin(time * 2 * .pi * 2)
        let grow = 1 + 0.035 * beat
        let centre = p(50, 52)

        for (x, y, phase) in [(10.0, 66.0, 0.25), (90.0, 70.0, 0.75)] {
            let wave = sin((time + phase) * 2 * .pi * 2)
            gitHubMark(&context, at: p(x, y - 3 * wave), side: 10 * u, color: amber.opacity(0.75 + 0.15 * wave))
        }
        for (x, y, phase) in [(14.0, 22.0, 0.0), (86.0, 30.0, 0.5)] {
            let wave = sin((time + phase) * 2 * .pi * 2)
            note(&context, at: p(x, y - 3 * wave), height: 10 * u, color: amber.opacity(0.8 + 0.15 * wave))
        }

        var c = context
        c.translateBy(x: centre.x, y: centre.y)
        c.scaleBy(x: grow, y: grow)
        c.translateBy(x: -centre.x, y: -centre.y)
        let outer = 36 * u, inner = outer * 0.48
        let points: [CGPoint] = (0 ..< 10).map { i in
            let r = i % 2 == 0 ? outer : inner
            let a = -Double.pi / 2 + Double(i) * .pi / 5
            return CGPoint(x: centre.x + r * cos(a), y: centre.y + r * sin(a))
        }
        // Each face is a triangle from the centre, lit by how squarely it turns to a light at the
        // top left, nudged by which side of its ridge it is on: that is what makes the bevel.
        let light = -Double.pi * 0.75
        for i in 0 ..< 10 {
            let a = points[i], b = points[(i + 1) % 10]
            let mid = CGPoint(x: (a.x + b.x) / 2 - centre.x, y: (a.y + b.y) / 2 - centre.y)
            let facing = cos(atan2(Double(mid.y), Double(mid.x)) - light)
            let lit = min(max((facing + 1) / 2 + (i % 2 == 0 ? 0.18 : -0.18), 0), 1)
            var face = Path()
            face.move(to: centre); face.addLine(to: a); face.addLine(to: b); face.closeSubpath()
            c.fill(face, with: .color(mix(0xE65100, 0xFFF59D, lit)))
        }
        var rim = Path()
        rim.addLines(points)
        rim.closeSubpath()
        c.stroke(rim, with: .color(rgb(0xB45309).opacity(0.55)), lineWidth: 1.2 * u)
        // The engraved note, and the glint at the top-left tip.
        note(&c, at: CGPoint(x: centre.x + 0.6 * u, y: centre.y + 2 * u), height: 13 * u, color: rgb(0x8D4A00).opacity(0.7))
        let glint = 0.5 + 0.5 * sin(time * 2 * .pi * 3)
        sparkle(&c, at: CGPoint(x: points[8].x + 2 * u, y: points[8].y + 2 * u), radius: (4 + 3 * glint) * u,
                color: .white.opacity(0.5 + 0.5 * glint))
    }

    // MARK: Small marks

    /// A quaver: an oval head tilted back, a stem and a flag. [height] is its full height.
    static func note(_ context: inout GraphicsContext, at: CGPoint, height h: CGFloat, color: Color) {
        let head = CGPoint(x: at.x - h * 0.12, y: at.y + h * 0.32)
        var tilted = context
        tilted.translateBy(x: head.x, y: head.y)
        tilted.rotate(by: .degrees(-22))
        tilted.fill(Path(ellipseIn: CGRect(x: -h * 0.23, y: -h * 0.16, width: h * 0.46, height: h * 0.32)), with: .color(color))
        let stemX = head.x + h * 0.46 * 0.42
        let top = at.y - h * 0.5
        context.fill(Path(CGRect(x: stemX - h * 0.06, y: top, width: h * 0.1, height: head.y - top)), with: .color(color))
        var flag = Path()
        flag.move(to: CGPoint(x: stemX, y: top))
        flag.addCurve(to: CGPoint(x: stemX + h * 0.26, y: top + h * 0.48),
                      control1: CGPoint(x: stemX + h * 0.12, y: top + h * 0.12),
                      control2: CGPoint(x: stemX + h * 0.36, y: top + h * 0.2))
        flag.addCurve(to: CGPoint(x: stemX, y: top + h * 0.22),
                      control1: CGPoint(x: stemX + h * 0.28, y: top + h * 0.3),
                      control2: CGPoint(x: stemX + h * 0.14, y: top + h * 0.24))
        flag.closeSubpath()
        context.fill(flag, with: .color(color))
    }

    /// GitHub's mark, the same outline as the app's GitHub icon, in a 24-point box; its two
    /// quarter-circle arcs are written as the curves that draw them.
    private static let gitHubPath =
        "M12,2C6.477,2 2,6.477 2,12c0,4.42 2.87,8.17 6.84,9.5c0.5,0.08 0.66,-0.23 0.66,-0.5c0,-0.23 0,-0.86 0,-1.69" +
        "c-2.77,0.6 -3.36,-1.34 -3.36,-1.34c-0.46,-1.16 -1.11,-1.47 -1.11,-1.47c-0.91,-0.62 0.07,-0.6 0.07,-0.6" +
        "c1,0.07 1.53,1.03 1.53,1.03c0.87,1.52 2.34,1.07 2.91,0.83c0.09,-0.65 0.35,-1.09 0.63,-1.34" +
        "c-2.22,-0.25 -4.55,-1.11 -4.55,-4.92c0,-1.11 0.38,-2 1.03,-2.71c-0.1,-0.25 -0.45,-1.29 0.1,-2.64" +
        "c0,0 0.84,-0.27 2.75,1.02c0.79,-0.22 1.65,-0.33 2.5,-0.33c0.85,0 1.71,0.11 2.5,0.33" +
        "c1.91,-1.29 2.75,-1.02 2.75,-1.02c0.55,1.35 0.2,2.39 0.1,2.64c0.65,0.71 1.03,1.6 1.03,2.71" +
        "c0,3.82 -2.34,4.66 -4.57,4.91c0.36,0.31 0.69,0.92 0.69,1.85c0,1.34 0,2.42 0,2.74" +
        "c0,0.27 0.16,0.59 0.67,0.5C19.14,20.16 22,16.42 22,12C22,6.477 17.523,2 12,2Z"

    static func gitHubMark(_ context: inout GraphicsContext, at: CGPoint, side: CGFloat, color: Color) {
        var c = context
        c.translateBy(x: at.x - side / 2, y: at.y - side / 2)
        c.fill(VectorPath.path(gitHubPath, side: side, viewport: 24), with: .color(color))
    }

    /// A four-pointed sparkle.
    static func sparkle(_ context: inout GraphicsContext, at: CGPoint, radius r: CGFloat, color: Color) {
        let w = r * 0.22
        var path = Path()
        path.move(to: CGPoint(x: at.x, y: at.y - r))
        path.addQuadCurve(to: CGPoint(x: at.x + r, y: at.y), control: CGPoint(x: at.x + w, y: at.y - w))
        path.addQuadCurve(to: CGPoint(x: at.x, y: at.y + r), control: CGPoint(x: at.x + w, y: at.y + w))
        path.addQuadCurve(to: CGPoint(x: at.x - r, y: at.y), control: CGPoint(x: at.x - w, y: at.y + w))
        path.addQuadCurve(to: CGPoint(x: at.x, y: at.y - r), control: CGPoint(x: at.x - w, y: at.y - w))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }
}
