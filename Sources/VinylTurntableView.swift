import SwiftUI

/// Vinyl turntable, ported 1:1 from VinylTurntable.kt.
/// The DISC (grooves + album label) rotates at 360°/8s and freezes on pause;
/// the sheen and the TONEARM never rotate with it — the arm pivots about its
/// bearing, swinging out (-16°) when paused and tracking inward as the song plays.
struct VinylTurntableView: View {
    let artURL: URL?
    let isPlaying: Bool
    let progress: Double
    let fallback: LinearGradient

    @State private var accumulated: Double = 0
    @State private var startedAt = Date()

    private static let degreesPerSecond = 45.0    // 360° / 8s
    private static let discCX = 0.46, discCY = 0.56, discR = 0.38
    private static let armBX = 0.81, armBY = 0.155
    private static let armRest = -16.0, armInner = 14.0

    private var armAngle: Double {
        isPlaying ? Self.armInner * (1 - min(max(progress, 0), 1)) : Self.armRest
    }

    var body: some View {
        GeometryReader { geo in
            let dim = min(geo.size.width, geo.size.height)
            let discSize = dim * (Self.discR * 2)
            let dx = dim * (Self.discCX - 0.5)
            let dy = dim * (Self.discCY - 0.5)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
                let angle = accumulated + (isPlaying
                    ? timeline.date.timeIntervalSince(startedAt) * Self.degreesPerSecond : 0)

                ZStack {
                    // 1. Fake soft drop shadow under the record.
                    Canvas { ctx, size in
                        let d = min(size.width, size.height)
                        let c = CGPoint(x: d * Self.discCX + d * 0.020, y: d * Self.discCY + d * 0.030)
                        let r = d * Self.discR * 1.12
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                            with: .radialGradient(
                                Gradient(colors: [.black.opacity(0.45), .black.opacity(0.18), .clear]),
                                center: c, startRadius: 0, endRadius: r))
                    }
                    .frame(width: dim, height: dim)

                    // 2. The disc — this is the only thing that spins.
                    VinylDisc(artURL: artURL, fallback: fallback)
                        .frame(width: discSize, height: discSize)
                        .rotationEffect(.degrees(angle))
                        .offset(x: dx, y: dy)

                    // 3. Fixed specular sheen (does NOT rotate).
                    Canvas { ctx, size in
                        let r = min(size.width, size.height) / 2
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: size.width / 2 - r, y: size.height / 2 - r,
                                                   width: r * 2, height: r * 2)),
                            with: .linearGradient(
                                Gradient(colors: [.white.opacity(0.12), .clear, .clear, .white.opacity(0.05)]),
                                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                    }
                    .frame(width: discSize, height: discSize)
                    .offset(x: dx, y: dy)

                    // 4. Tonearm — pivots about its bearing, never spins with the disc.
                    Canvas { ctx, size in drawTonearm(ctx, size) }
                        .frame(width: dim, height: dim)
                        .rotationEffect(.degrees(armAngle),
                                        anchor: UnitPoint(x: Self.armBX, y: Self.armBY))
                        .animation(.spring(response: 0.95, dampingFraction: 0.85), value: armAngle)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .onChange(of: isPlaying) {
            if isPlaying {
                startedAt = Date()
            } else {
                accumulated += Date().timeIntervalSince(startedAt) * Self.degreesPerSecond
            }
        }
    }

    // MARK: Tonearm

    private func drawTonearm(_ ctx: GraphicsContext, _ size: CGSize) {
        let d = min(size.width, size.height)
        let b = CGPoint(x: d * Self.armBX, y: d * Self.armBY)
        let e = CGPoint(x: d * Self.armBX, y: d * 0.62)
        let h = CGPoint(x: d * 0.73, y: d * 0.76)

        let chrome = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Color(hex: 0x6E6F75), Color(hex: 0xEDEEF2),
                              Color(hex: 0x93949A), Color(hex: 0x45464C)]),
            startPoint: CGPoint(x: d * 0.66, y: 0), endPoint: CGPoint(x: d * 0.90, y: 0))

        var tube = Path()
        tube.move(to: b)
        tube.addLine(to: e)
        tube.addCurve(to: h,
                      control1: CGPoint(x: d * Self.armBX, y: d * 0.70),
                      control2: CGPoint(x: d * 0.775, y: d * 0.72))

        // Shadows (light from top-left → shadows fall down-right).
        var sh = ctx
        sh.translateBy(x: d * 0.014, y: d * 0.022)
        sh.stroke(tube, with: .color(.black.opacity(0.10)),
                  style: StrokeStyle(lineWidth: d * 0.036, lineCap: .round))
        sh.stroke(tube, with: .color(.black.opacity(0.20)),
                  style: StrokeStyle(lineWidth: d * 0.020, lineCap: .round))
        sh.fill(circle(b, d * 0.098), with: .color(.black.opacity(0.22)))
        sh.fill(circle(h, d * 0.055), with: .radialGradient(
            Gradient(colors: [.black.opacity(0.28), .clear]),
            center: h, startRadius: 0, endRadius: d * 0.055))

        // Chrome tube: dark outline → metal → specular core.
        ctx.stroke(tube, with: .color(Color(hex: 0x1B1B1E)),
                   style: StrokeStyle(lineWidth: d * 0.019, lineCap: .round))
        ctx.stroke(tube, with: chrome, style: StrokeStyle(lineWidth: d * 0.014, lineCap: .round))
        ctx.stroke(tube, with: .color(.white.opacity(0.85)),
                   style: StrokeStyle(lineWidth: d * 0.0045, lineCap: .round))

        // Counterweight stack above the bearing.
        let stack = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Color(hex: 0x8E8F95), Color(hex: 0xF7F8FA),
                              Color(hex: 0xB9BAC0), Color(hex: 0x4A4B50)]),
            startPoint: CGPoint(x: b.x - d * 0.030, y: 0), endPoint: CGPoint(x: b.x + d * 0.030, y: 0))
        func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ hh: CGFloat, _ r: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: hh), cornerRadius: r)
        }
        ctx.fill(rr(b.x - d * 0.018, d * 0.052, d * 0.036, d * 0.030, d * 0.006), with: stack)
        ctx.fill(rr(b.x - d * 0.011, d * 0.038, d * 0.022, d * 0.016, d * 0.004),
                 with: .color(Color(hex: 0x3E3F44)))
        ctx.fill(rr(b.x - d * 0.029, d * 0.017, d * 0.058, d * 0.022, d * 0.008), with: stack)
        ctx.fill(rr(b.x - d * 0.029, d * 0.033, d * 0.058, d * 0.006, d * 0.003),
                 with: .color(.black.opacity(0.25)))
        var catchLight = Path()
        catchLight.move(to: CGPoint(x: b.x - d * 0.024, y: d * 0.020))
        catchLight.addLine(to: CGPoint(x: b.x + d * 0.020, y: d * 0.020))
        ctx.stroke(catchLight, with: .color(.white.opacity(0.55)),
                   style: StrokeStyle(lineWidth: d * 0.0025, lineCap: .round))

        // Gimbal bearing.
        ctx.fill(circle(b, d * 0.095), with: .radialGradient(
            Gradient(colors: [Color(hex: 0x46464B), Color(hex: 0x1C1C1F), Color(hex: 0x0C0C0E)]),
            center: CGPoint(x: b.x - d * 0.022, y: b.y - d * 0.022),
            startRadius: 0, endRadius: d * 0.135))
        let arcRect = CGRect(x: b.x - d * 0.091, y: b.y - d * 0.091, width: d * 0.182, height: d * 0.182)
        var rim = Path()
        rim.addArc(center: CGPoint(x: arcRect.midX, y: arcRect.midY), radius: d * 0.091,
                   startAngle: .degrees(-165), endAngle: .degrees(-85), clockwise: false)
        ctx.stroke(rim, with: .color(.white.opacity(0.30)),
                   style: StrokeStyle(lineWidth: d * 0.004, lineCap: .round))
        var shade = Path()
        shade.addArc(center: CGPoint(x: arcRect.midX, y: arcRect.midY), radius: d * 0.091,
                     startAngle: .degrees(20), endAngle: .degrees(100), clockwise: false)
        ctx.stroke(shade, with: .color(.black.opacity(0.35)),
                   style: StrokeStyle(lineWidth: d * 0.004, lineCap: .round))
        ctx.fill(circle(b, d * 0.058), with: .linearGradient(
            Gradient(colors: [Color(hex: 0xC6C7CD), Color(hex: 0xA7A8AE), Color(hex: 0x87888E)]),
            startPoint: CGPoint(x: b.x - d * 0.045, y: b.y - d * 0.045),
            endPoint: CGPoint(x: b.x + d * 0.045, y: b.y + d * 0.045)))
        ctx.stroke(circle(b, d * 0.058), with: .color(.black.opacity(0.35)), lineWidth: d * 0.003)
        ctx.stroke(circle(CGPoint(x: b.x - d * 0.004, y: b.y - d * 0.004), d * 0.052),
                   with: .color(.white.opacity(0.25)), lineWidth: d * 0.0022)
        ctx.fill(circle(b, d * 0.009), with: .radialGradient(
            Gradient(colors: [Color(hex: 0xEDEEF2), Color(hex: 0x6E6F75)]),
            center: CGPoint(x: b.x - d * 0.003, y: b.y - d * 0.003),
            startRadius: 0, endRadius: d * 0.012))
        ctx.fill(circle(b, d * 0.0035), with: .color(Color(hex: 0x2A2B2F)))

        // Headshell + cartridge, rotated 138° about the stylus point.
        ctx.fill(circle(h, d * 0.011), with: chrome)
        var head = ctx
        head.translateBy(x: h.x, y: h.y)
        head.rotate(by: .degrees(138))
        head.translateBy(x: -h.x, y: -h.y)
        head.fill(rr(h.x, h.y - d * 0.014, d * 0.075, d * 0.028, d * 0.007),
                  with: .color(Color(hex: 0x131316)))
        head.fill(rr(h.x, h.y - d * 0.014, d * 0.075, d * 0.008, d * 0.004), with: chrome)
        var lift = Path()
        lift.move(to: CGPoint(x: h.x + d * 0.008, y: h.y - d * 0.012))
        lift.addLine(to: CGPoint(x: h.x - d * 0.010, y: h.y - d * 0.026))
        head.stroke(lift, with: chrome, style: StrokeStyle(lineWidth: d * 0.0045, lineCap: .round))
        head.fill(circle(CGPoint(x: h.x + d * 0.064, y: h.y + d * 0.017), d * 0.0055),
                  with: .color(Color(hex: 0x0A0A0C)))
        head.fill(circle(CGPoint(x: h.x + d * 0.063, y: h.y + d * 0.015), d * 0.002),
                  with: .color(.white.opacity(0.8)))
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}

/// The record itself: matte grooved disc + the album art as its centre label.
private struct VinylDisc: View {
    let artURL: URL?
    let fallback: LinearGradient

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2
                func circle(_ rad: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
                }
                // Matte-black disc, lit from the top-left.
                ctx.fill(circle(r), with: .radialGradient(
                    Gradient(colors: [Color(hex: 0x3A3A3D), Color(hex: 0x141416), Color(hex: 0x060607)]),
                    center: CGPoint(x: c.x - r * 0.25, y: c.y - r * 0.25),
                    startRadius: 0, endRadius: r * 1.3))
                // Concentric grooves.
                var gr = r * 0.46
                while gr < r * 0.97 {
                    ctx.stroke(circle(gr), with: .color(.white.opacity(0.05)), lineWidth: 1.2)
                    gr += r * 0.016
                }
                // Track separators + rim highlight.
                for sep in [0.56, 0.72, 0.88] {
                    ctx.stroke(circle(r * sep), with: .color(.white.opacity(0.10)), lineWidth: 1.6)
                }
                ctx.stroke(circle(r * 0.99), with: .color(.white.opacity(0.12)), lineWidth: 2)
            }

            // Album label — 42% of the disc, rotates with it.
            GeometryReader { g in
                let side = min(g.size.width, g.size.height) * 0.42
                RemoteImage(url: artURL) { fallback }
                    .frame(width: side, height: side)
                    .clipShape(Circle())
                    .position(x: g.size.width / 2, y: g.size.height / 2)
            }

            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2
                func circle(_ rad: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
                }
                ctx.stroke(circle(r * 0.42), with: .color(.black.opacity(0.35)), lineWidth: 2)
                ctx.fill(circle(r * 0.035), with: .color(Color(hex: 0x0B0B0C)))
                ctx.fill(circle(r * 0.018), with: .color(Color(hex: 0x2A2A2C)))
            }
        }
    }
}
