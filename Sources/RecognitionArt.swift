import SwiftUI

/// Blazify Project (C) 2026
/// Licensed under GPL-3.0

/// The pictures on the recognition screen: a sound wave in the big button,
/// rings of sound leaving it, notes drifting up while it listens, sparks drawn
/// inward while it searches, and the wave falling flat when nothing was found.
///
/// All of it is driven by the clock, like the loader: nothing is scheduled, and
/// nothing is left running once the screen moves on to another state.
enum RecognitionArt {
    /// How tall each bar of the wave stands at rest — tall in the middle, so it
    /// reads as sound rather than as a bar chart.
    static let bars: [CGFloat] = [0.42, 0.68, 1, 0.8, 1, 0.68, 0.42]

    /// A music note built from shapes — head, stem and flag — in a `tall`-point
    /// square. Drawn rather than taken from a symbol, so it can be any size each
    /// frame without being re-rendered as text.
    static func drawNote(in gc: inout GraphicsContext, tall: CGFloat, color: Color) {
        let stem = tall * 0.09
        let stemLeft = tall * 0.56
        let shading = GraphicsContext.Shading.color(color)
        gc.fill(Path(ellipseIn: CGRect(x: tall * 0.2, y: tall * 0.7, width: tall * 0.44, height: tall * 0.3)),
                with: shading)
        gc.fill(Path(CGRect(x: stemLeft, y: tall * 0.08, width: stem, height: tall * 0.78)), with: shading)
        var flag = Path()
        flag.move(to: CGPoint(x: stemLeft + stem, y: tall * 0.08))
        flag.addCurve(to: CGPoint(x: tall * 0.88, y: tall * 0.56),
                      control1: CGPoint(x: tall * 0.72, y: tall * 0.26),
                      control2: CGPoint(x: tall * 0.98, y: tall * 0.28))
        flag.addCurve(to: CGPoint(x: stemLeft + stem, y: tall * 0.32),
                      control1: CGPoint(x: tall * 0.86, y: tall * 0.4),
                      control2: CGPoint(x: tall * 0.74, y: tall * 0.36))
        flag.closeSubpath()
        gc.fill(flag, with: shading)
    }

    /// How far through a loop of `seconds` the clock is, 0…1.
    static func lap(_ date: Date, _ seconds: Double) -> CGFloat {
        CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: seconds) / seconds)
    }
}

/// A sound wave standing where a microphone would: bars rising and falling,
/// tall in the middle. Barely stirring while it waits for a tap, and dancing
/// once it is really listening.
struct SoundWaveBars: View {
    var color: Color
    var lively: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let phase = RecognitionArt.lap(timeline.date, lively ? 0.9 : 2.6)
            Canvas { gc, size in
                let bars = RecognitionArt.bars
                let barWidth = size.width / (CGFloat(bars.count) * 2 - 1)
                let swing: CGFloat = lively ? 0.5 : 0.14
                for (index, tallness) in bars.enumerated() {
                    let wave = sin(2 * .pi * (phase + CGFloat(index) * 0.17))
                    let share = min(max(tallness * (1 - swing + swing * wave), 0.14), 1)
                    let height = size.height * share
                    let rect = CGRect(x: CGFloat(index) * barWidth * 2, y: (size.height - height) / 2,
                                      width: barWidth, height: height)
                    gc.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Rings of sound travelling outward from the button and fading as they go.
struct SoundRipples: View {
    var color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let travel = RecognitionArt.lap(timeline.date, 2.1)
            Canvas { gc, size in
                let outer = min(size.width, size.height) / 2
                let inner = outer * 0.6
                let rings = 3
                for ring in 0..<rings {
                    let along = (travel + CGFloat(ring) / CGFloat(rings)).truncatingRemainder(dividingBy: 1)
                    let radius = inner + (outer - inner) * along
                    let rect = CGRect(x: size.width / 2 - radius, y: size.height / 2 - radius,
                                      width: radius * 2, height: radius * 2)
                    gc.stroke(Path(ellipseIn: rect),
                              with: .color(color.opacity(Double((1 - along) * 0.55))),
                              lineWidth: 3)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Music notes drifting up the screen behind the button while it listens: a
/// few, not a shower, and faint, so they are something going on behind what
/// matters rather than something to read.
struct FlyingNotes: View {
    var color: Color

    /// Where each note rises (a share of the width), where in the loop it
    /// starts, how many times it rises per loop, and how tall it is.
    private static let flights: [(across: CGFloat, start: CGFloat, laps: CGFloat, size: CGFloat)] = [
        (0.10, 0.05, 1, 26), (0.88, 0.22, 1, 20), (0.26, 0.41, 2, 18), (0.72, 0.58, 1, 28),
        (0.50, 0.74, 1, 22), (0.05, 0.87, 2, 16), (0.94, 0.66, 2, 18), (0.36, 0.14, 1, 20),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = RecognitionArt.lap(timeline.date, 11)
            Canvas { gc, size in
                let sway: CGFloat = 22
                for flight in Self.flights {
                    let along = (phase * flight.laps + flight.start).truncatingRemainder(dividingBy: 1)
                    let x = size.width * flight.across + sway * sin(2 * .pi * (along * 2 + flight.start))
                    let y = size.height * (1.05 - 1.15 * along)
                    // In over the first stretch, out over the last.
                    let fade = min(along / 0.15, 1) * min((1 - along) / 0.3, 1)
                    let tall = flight.size
                    var note = gc
                    note.translateBy(x: x - tall / 2, y: y)
                    note.translateBy(x: tall / 2, y: tall / 2)
                    note.rotate(by: .degrees(Double(11 * sin(2 * .pi * along))))
                    note.translateBy(x: -tall / 2, y: -tall / 2)
                    RecognitionArt.drawNote(in: &note, tall: tall, color: color.opacity(Double(fade * 0.42)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Sparks drawn in from the edges to the middle while the song is looked up.
struct FindingSparks: View {
    var color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let phase = RecognitionArt.lap(timeline.date, 2.8)
            Canvas { gc, size in
                let sparks = 9
                let reach = min(size.width, size.height) * 0.62
                let inner: CGFloat = 84
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for spark in 0..<sparks {
                    let along = (phase + CGFloat(spark) * 0.37).truncatingRemainder(dividingBy: 1)
                    let angle = 2 * .pi * CGFloat(spark) / CGFloat(sparks) + along * 0.5
                    let distance = inner + (reach - inner) * (1 - along)
                    let radius = 2.5 + CGFloat(spark % 3)
                    let dot = CGRect(x: center.x + cos(angle) * distance - radius,
                                     y: center.y + sin(angle) * distance - radius,
                                     width: radius * 2, height: radius * 2)
                    gc.fill(Path(ellipseIn: dot),
                            with: .color(color.opacity(Double(sin(.pi * along) * 0.6))))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A ring turning around a note while the song is looked up: busy, but calm.
struct FindingRing: View {
    var color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let turn = Double(RecognitionArt.lap(timeline.date, 2)) * 360
            ZStack {
                Circle()
                    .strokeBorder(AngularGradient(gradient: Gradient(colors: [
                        color, color.opacity(0.5), .clear, color.opacity(0.5), color,
                    ]), center: .center), lineWidth: 4)
                    .rotationEffect(.degrees(turn))
                Image(systemName: "music.note")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .accessibilityHidden(true)
    }
}

/// What came of listening when nothing was found: the wave falls flat inside a
/// grey circle, a few notes drop away out of it, and a question mark stays.
/// It plays once and rests, since nothing is happening any more.
struct SongNotFoundArt: View {
    @Environment(\.palette) private var palette
    @State private var start = Date()
    @State private var resting = false

    private static let seconds: Double = 1.4
    /// Where each note drops from (a share of the circle's radius, left or
    /// right of centre) and how far into the fall it waits before it goes.
    private static let dropped: [(side: CGFloat, delay: CGFloat)] = [(-0.55, 0.2), (0.1, 0.05), (0.62, 0.32)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: resting)) { timeline in
            let raw = min(max(timeline.date.timeIntervalSince(start) / Self.seconds, 0), 1)
            let settle = LoaderStory.ease(CGFloat(raw))
            Canvas { gc, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.36
                gc.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(palette.surfaceHigh))

                // The wave, falling flat.
                let bars = RecognitionArt.bars
                let across = radius * 1.12
                let barWidth = across / (CGFloat(bars.count) * 2 - 1)
                let left = center.x - across / 2
                for (index, tallness) in bars.enumerated() {
                    let height = radius * 1.05 * (tallness + (0.12 - tallness) * settle)
                    let rect = CGRect(x: left + CGFloat(index) * barWidth * 2, y: center.y - height / 2,
                                      width: barWidth, height: height)
                    gc.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                            with: .color(palette.onSurfaceVariant))
                }

                // A few notes dropping out of it and fading on the way down.
                let tall: CGFloat = 22
                for note in Self.dropped {
                    let along = min(max((settle - note.delay) / (1 - note.delay), 0), 1)
                    var n = gc
                    n.translateBy(x: center.x + radius * note.side - tall / 2,
                                  y: center.y + radius * 0.3 + size.height * 0.34 * along)
                    RecognitionArt.drawNote(in: &n, tall: tall,
                                            color: palette.onSurfaceVariant.opacity(Double(sin(.pi * along) * 0.7)))
                }

                // The question mark, growing into its corner.
                let badge = min(size.width, size.height) * 0.118 * settle
                if badge > 0.5 {
                    let spot = CGPoint(x: size.width * 0.773, y: size.height * 0.218)
                    gc.fill(Path(ellipseIn: CGRect(x: spot.x - badge, y: spot.y - badge,
                                                   width: badge * 2, height: badge * 2)),
                            with: .color(Color(red: 0.86, green: 0.24, blue: 0.24)))
                    gc.draw(Text("?")
                                .font(.system(size: badge * 1.08, weight: .bold))
                                .foregroundColor(.white),
                            at: spot)
                }
            }
        }
        .accessibilityHidden(true)
        .task {
            // Long enough for the fall to finish; after that the clock can stop.
            try? await Task.sleep(nanoseconds: UInt64((Self.seconds + 0.1) * 1_000_000_000))
            resting = true
        }
    }
}
