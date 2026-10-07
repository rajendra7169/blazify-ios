import SwiftUI
import UIKit

/// Blazify Project (C) 2026
/// Licensed under GPL-3.0

/// Blazify's loading animation: the logo telling a short story, over and over.
/// A play button settles into place, the flame grows around it, the headband
/// sweeps over and the ear cups come down and bounce, sound rolls out of them
/// and music notes drift up, and then it all eases back into the play button.
/// Something is always about to happen, so a wait is watched rather than
/// counted. The same drawing and timing as the Android app's loader.
struct BlazeLoader: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 44
    /// Overrides the theme's accent, for a loader on a coloured surface.
    var tint: Color?

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { gc, canvasSize in
                let t = CGFloat(timeline.date.timeIntervalSince(start))
                let side = min(canvasSize.width, canvasSize.height)
                let k = side / BlazeLogoShapes.viewSize
                gc.translateBy(x: (canvasSize.width - side) / 2, y: (canvasSize.height - side) / 2)
                gc.scaleBy(x: k, y: k)
                gc.translateBy(x: -BlazeLogoShapes.viewLeft, y: -BlazeLogoShapes.viewTop)
                LoaderStory.draw(in: &gc, t: t, colors: LoaderColors(tint ?? palette.accent))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Loading")
    }
}

/// The loader's colours, all from one base so it follows the theme.
struct LoaderColors {
    let top: Color, bottom: Color, cups: Color, cream: Color, notes: Color, glow: Color

    init(_ base: Color) {
        top = base
        bottom = Self.mix(base, UIColor(red: 1, green: 0.30, blue: 0.10, alpha: 1), 0.35)
        cups = Self.mix(base, .white, 0.25)
        cream = Self.mix(base, .white, 0.88)
        notes = Self.mix(base, .white, 0.55)
        glow = base
    }

    static func mix(_ a: Color, _ b: UIColor, _ f: CGFloat) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(a).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f, blue: b1 + (b2 - b1) * f)
    }
}

/// The logo's parts, parsed once for the whole app.
private enum LoaderPaths {
    static let band = BlazeLogoShapes.path(BlazeLogoShapes.band)
    static let cupLeft = BlazeLogoShapes.path(BlazeLogoShapes.cupLeft)
    static let cupRight = BlazeLogoShapes.path(BlazeLogoShapes.cupRight)
    static let flame = BlazeLogoShapes.path(BlazeLogoShapes.flame + " " + BlazeLogoShapes.play)
    static let play = BlazeLogoShapes.path(BlazeLogoShapes.play)
    static let rippleLeft: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 150, y: 545))
        p.addQuadCurve(to: CGPoint(x: 150, y: 695), control: CGPoint(x: 80, y: 620))
        return p
    }()
    static let rippleRight: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 874, y: 545))
        p.addQuadCurve(to: CGPoint(x: 874, y: 695), control: CGPoint(x: 944, y: 620))
        return p
    }()
}

/// The story itself, shared with the launch screen's logo.
enum LoaderStory {
    /// The story's length; the life on top of it runs on its own shorter rhythms.
    static let seconds: CGFloat = 4
    /// One full hop and landing of an ear cup.
    static let cupBounce: CGFloat = 0.9

    static func draw(in gc: inout GraphicsContext, t: CGFloat, colors c: LoaderColors) {
        let u = t.truncatingRemainder(dividingBy: seconds) / seconds
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [c.top, c.bottom]),
            startPoint: CGPoint(x: 512, y: 180), endPoint: CGPoint(x: 512, y: 780))

        // A warm glow gathering behind the logo while it is whole.
        let glow = envelope(u, 0.08, 0.45, 0.78, 1)
        if glow > 0 {
            let r = 300 * (0.5 + 0.5 * glow)
            let rect = CGRect(x: 512 - r, y: 560 - r, width: 2 * r, height: 2 * r)
            gc.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [c.glow.opacity(0.42 * glow), .clear]),
                center: CGPoint(x: 512, y: 560), startRadius: 0, endRadius: r))
        }

        // Sound rolling out of the ear cups, and music notes rising off the flame,
        // while the logo is whole.
        let alive = envelope(u, 0.48, 0.56, 0.76, 0.88)
        if alive > 0 {
            for start: CGFloat in [0, 0.8] {
                let k = (t + start).truncatingRemainder(dividingBy: 1.6) / 1.6
                let out = 70 * easeOut(k)
                let a = 0.9 * (1 - k) * alive
                let style = StrokeStyle(lineWidth: 20, lineCap: .round)
                gc.stroke(LoaderPaths.rippleLeft.offsetBy(dx: -out, dy: 0), with: .color(c.top.opacity(a)), style: style)
                gc.stroke(LoaderPaths.rippleRight.offsetBy(dx: out, dy: 0), with: .color(c.top.opacity(a)), style: style)
            }
            let notes: [(CGPoint, CGFloat)] = [(CGPoint(x: 470, y: 300), -1), (CGPoint(x: 548, y: 286), 1), (CGPoint(x: 512, y: 262), -1)]
            for (i, (from, side)) in notes.enumerated() {
                let k = (t + 2.2 - CGFloat(i) * 0.73).truncatingRemainder(dividingBy: 2.2) / 2.2
                let a = (k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8) * alive
                guard a > 0 else { continue }
                let first = ease(ramp(k, 0, 0.5))
                let second = ease(ramp(k, 0.5, 1))
                var n = gc
                n.translateBy(x: from.x + side * (14 * first - 20 * second), y: from.y - 70 * first - 80 * second)
                n.rotate(by: .degrees(Double(side * (6 * first - 10 * second))))
                n.opacity = Double(a)
                let note = Text(Image(systemName: i == 1 ? "music.note.list" : "music.note"))
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(c.notes)
                n.draw(note, at: .zero)
            }
        }

        // The headband sweeps in along its own line, holds, then lets go from where it began.
        let reveal = ease(ramp(u, 0.20, 0.46))
        let erase = ease(ramp(u, 0.78, 0.96))
        if reveal > erase {
            let line = BlazeLogoShapes.sweep.trimmedPath(from: erase, to: reveal)
                .strokedPath(StrokeStyle(lineWidth: 200, lineCap: .round))
            var band = gc
            band.clip(to: line)
            band.fill(LoaderPaths.band, with: shading)
        }

        // The ear cups float down into place, then bounce, one after the other.
        let cups = envelope(u, 0.34, 0.50, 0.78, 0.92)
        if cups > 0 {
            drawCup(&gc, LoaderPaths.cupLeft, t: t, offset: 0, shown: cups, color: c.cups)
            drawCup(&gc, LoaderPaths.cupRight, t: t, offset: cupBounce / 2, shown: cups, color: c.cups)
        }

        // The flame grows around the play button and keeps swaying.
        let flame = envelope(u, 0.08, 0.30, 0.80, 0.96)
        if flame > 0 {
            let b = LoaderPaths.flame.boundingRect
            let pivot = CGPoint(x: b.midX, y: b.minY + b.height * 0.85)
            let sway = sin(t * 2 * .pi / 3.2)
            var f = gc
            f.opacity = Double(flame)
            f.translateBy(x: pivot.x, y: pivot.y)
            f.rotate(by: .degrees(Double(2.2 * sway)))
            f.scaleBy(x: flame * (1 - 0.012 * sway), y: flame * (1 + 0.015 * sway))
            f.translateBy(x: -pivot.x, y: -pivot.y)
            f.fill(LoaderPaths.flame, with: shading, style: FillStyle(eoFill: true))
        }

        // The play button: large and warm at the start, settled and pale inside the flame.
        let settled = envelope(u, 0.06, 0.26, 0.80, 1)
        let pale = envelope(u, 0.08, 0.26, 0.80, 0.98)
        let pb = LoaderPaths.play.boundingRect
        var p = gc
        let s = 2.2 - 1.2 * settled
        p.translateBy(x: pb.midX, y: pb.midY)
        p.scaleBy(x: s, y: s)
        p.translateBy(x: -pb.midX, y: -pb.midY)
        p.fill(LoaderPaths.play, with: .color(c.top))
        p.fill(LoaderPaths.play, with: .color(c.cream.opacity(Double(pale))))
    }

    private static func drawCup(_ gc: inout GraphicsContext, _ path: Path, t: CGFloat, offset: CGFloat,
                                shown: CGFloat, color: Color) {
        let b = path.boundingRect
        // A small hop, then a soft squash as it lands.
        let p = (t + offset).truncatingRemainder(dividingBy: cupBounce) / cupBounce
        var lift: CGFloat = 0
        var squash: CGFloat = 0
        if p < 0.55 { lift = sin(.pi * p / 0.55) } else { squash = sin(.pi * (p - 0.55) / 0.45) }
        let hop = 16 * lift * shown
        var g = gc
        g.opacity = Double(shown)
        g.translateBy(x: 0, y: -40 * (1 - shown) - hop)
        let grow = 0.6 + 0.4 * shown
        g.translateBy(x: b.midX, y: b.minY)
        g.scaleBy(x: grow, y: grow)
        g.translateBy(x: -b.midX, y: -b.minY)
        g.translateBy(x: b.midX, y: b.maxY)
        g.scaleBy(x: 1 + 0.05 * squash, y: 1 - 0.07 * squash)
        g.translateBy(x: -b.midX, y: -b.maxY)
        g.fill(path, with: .color(color))
    }

    /// 0 before `a`, 1 after `b`, straight in between.
    static func ramp(_ u: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max((u - a) / (b - a), 0), 1) }

    /// Slow in, slow out.
    static func ease(_ x: CGFloat) -> CGFloat {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    static func easeOut(_ x: CGFloat) -> CGFloat { 1 - pow(1 - x, 3) }

    /// Eases up from 0 to 1 between `inStart` and `inEnd`, holds, then eases back to 0 by `outEnd`.
    static func envelope(_ u: CGFloat, _ inStart: CGFloat, _ inEnd: CGFloat, _ outStart: CGFloat, _ outEnd: CGFloat) -> CGFloat {
        ease(ramp(u, inStart, inEnd)) * (1 - ease(ramp(u, outStart, outEnd)))
    }
}
