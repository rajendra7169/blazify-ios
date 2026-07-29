import SwiftUI
import UIKit

/// The player seek bar in whichever style Look & Feel selects, each ported from
/// its Android counterpart:
///
/// - **Slim** — the 8pt Apple-Music bar (Blaze default).
/// - **Capsule** — `CapsuleSeekBar.kt`: a thin 3pt track with a 20pt pill riding
///   it that carries the "0:36 / 2:59" time label; the fill runs to the pill's
///   middle.
/// - **Wavy** — `WavySlider.kt`: an animated wave over the played portion, flat
///   track ahead, that settles flat while paused.
/// - **Squiggly** — `SquigglySlider.kt`: the same idea with a much tighter,
///   livelier squiggle.
struct SlimSlider: View {
    @Binding var value: Double        // 0...1
    let active: Color
    /// Seconds, so the capsule style can print its time label. 0 hides times.
    var duration: Double = 0
    /// The wave styles flatten while paused, as Android's do.
    var isPlaying: Bool = true
    let onCommit: (Double) -> Void

    @ObservedObject private var look = LookFeel.shared

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Group {
                switch look.sliderStyle {
                case .slim:
                    SlimTrack(fraction: value, active: active)
                case .capsule:
                    CapsuleTrack(fraction: value, active: active,
                                 label: timeLabel, compact: false)
                case .wavy:
                    WavyTrack(fraction: value, active: active,
                              squiggly: look.squigglySlider, isPlaying: isPlaying)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in value = clamp(g.location.x / w) }
                    .onEnded { g in
                        let v = clamp(g.location.x / w)
                        value = v
                        onCommit(v)
                    },
            )
        }
        .frame(height: look.sliderStyle == .capsule ? 24 : 24)
    }

    private var timeLabel: String {
        guard duration > 0 else { return "•" }
        return "\(clock(value * duration)) / \(clock(duration))"
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
}

// MARK: - Slim

/// 8pt round-capped bar; the fill never goes narrower than it is tall, so the
/// left edge stays rounded instead of squashing flat.
struct SlimTrack: View {
    let fraction: Double
    let active: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let filled = min(max(w * fraction, 8), w)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.24)).frame(height: 8)
                Capsule().fill(active).frame(width: filled, height: 8)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Capsule (CapsuleSeekBar.kt)

/// Thin track with a time-label pill riding along it. The pill travels between
/// the track ends rather than overhanging them, exactly as the Kotlin does.
struct CapsuleTrack: View {
    let fraction: Double
    let active: Color
    let label: String
    var compact: Bool

    private var pillHeight: CGFloat { compact ? 14 : 20 }
    private var trackHeight: CGFloat { compact ? 2.5 : 3 }
    private var labelSize: CGFloat { compact ? 7 : 10 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pillWidth = min(templateWidth + (compact ? 16 : 28), w)
            let travel = max(w - pillWidth, 0)
            let x = travel * fraction

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.24))
                    .frame(height: trackHeight)
                Capsule().fill(active)
                    .frame(width: x + pillWidth / 2, height: trackHeight)
                Capsule().fill(active)
                    .frame(width: pillWidth, height: pillHeight)
                    .overlay(
                        Text(label)
                            .font(.system(size: labelSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(active.isLight ? .black : .white)
                            .lineLimit(1),
                    )
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    /// Width of the label with every digit swapped for an "8", in monospaced
    /// digits — so the pill keeps ONE width while the seconds tick, instead of
    /// breathing as narrow digits come and go.
    private var templateWidth: CGFloat {
        let template = String(label.map { $0.isNumber ? "8" : $0 })
        let font = UIFont.monospacedDigitSystemFont(ofSize: labelSize, weight: .semibold)
        return (template as NSString).size(withAttributes: [.font: font]).width
    }
}

// MARK: - Wavy / Squiggly (WavySlider.kt / SquigglySlider.kt)

/// Animated wave over the played portion, flat ahead, with a bar thumb at the
/// boundary. The wave rolls while playing and settles flat when paused.
struct WavyTrack: View {
    let fraction: Double
    let active: Color
    let squiggly: Bool
    let isPlaying: Bool
    /// Pickers draw the same slider smaller, the way the Kotlin dialog tiles do.
    var compact = false

    // Straight from the Kotlin. WavySlider: wavelength 40dp, stroke 4dp,
    // thumbRadius 8dp, gapSize thumbRadius + 4dp, waveSpeed = wavelength.
    // SquigglySlider: waveLength 80px ≈ 27dp, lineAmplitude 6px ≈ 2.5dp,
    // strokeWidth 5dp, phaseSpeed 24px ≈ 8dp/s, bar thumb 5dp wide.
    private var s: CGFloat { compact ? 0.66 : 1 }
    private var wavelength: CGFloat { (squiggly ? 27 : 40) * s }
    private var amplitude: CGFloat { (squiggly ? 2.5 : 5) * s }
    private var stroke: CGFloat { (squiggly ? 5 : 4) * s }
    private var speed: CGFloat { (squiggly ? 8 : 40) * s }
    private var gap: CGFloat { 12 * s }
    private var thumbRadius: CGFloat { 8 * s }

    /// Squiggly tints the unplayed side with the accent at 77/255; wavy leaves
    /// the flat track in the player's inactive white.
    private var inactive: Color { squiggly ? active.opacity(0.302) : .white.opacity(0.24) }

    private var lineHeight: CGFloat { (amplitude + stroke) * 2 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            GeometryReader { geo in
                let w = geo.size.width
                let x = w * max(0, min(1, fraction))
                // Crests roll forward with playback and freeze when paused.
                let phase = isPlaying
                    ? CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                        .truncatingRemainder(dividingBy: 10_000) * speed
                    : 0
                let amp = isPlaying ? amplitude : 0

                ZStack(alignment: .leading) {
                    if squiggly {
                        // One continuous line the full width, relaxing to flat
                        // over 1.5 wavelengths past the thumb, drawn in two
                        // colours split at the playhead.
                        let path = WavePath(amplitude: amp, wavelength: wavelength,
                                            phase: phase, fadeFrom: x,
                                            fadeLength: wavelength * 1.5)
                        path.stroke(inactive, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                            .mask(alignment: .trailing) { Rectangle().frame(width: max(w - x, 0)) }
                        path.stroke(active, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                            .mask(alignment: .leading) { Rectangle().frame(width: x) }

                        // Vertical bar thumb, half-height amplitude + stroke.
                        Capsule().fill(active)
                            .frame(width: 5 * s, height: lineHeight)
                            .offset(x: min(max(x - 2.5 * s, 0), max(w - 5 * s, 0)))
                    } else {
                        // Material's wavy indicator: wave up to the thumb, a
                        // gap, then the flat track.
                        WavePath(amplitude: amp, wavelength: wavelength, phase: phase)
                            .stroke(active, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                            .mask(alignment: .leading) { Rectangle().frame(width: max(x - gap, 0)) }

                        Capsule().fill(inactive)
                            .frame(width: max(w - x - gap, 0), height: stroke)
                            .offset(x: min(x + gap, w))

                        Circle().fill(active)
                            .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                            .offset(x: min(max(x - thumbRadius, 0), max(w - thumbRadius * 2, 0)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isPlaying)
                .frame(width: w, height: geo.size.height, alignment: .leading)
            }
        }
        .frame(height: max(lineHeight, thumbRadius * 2))
    }
}

struct WavePath: Shape {
    var amplitude: CGFloat
    var wavelength: CGFloat
    var phase: CGFloat
    /// Squiggly tapers the wave to flat past the playhead; wavy never fades.
    var fadeFrom: CGFloat = .infinity
    var fadeLength: CGFloat = 1

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0, wavelength > 0 else { return path }
        let mid = rect.midY

        // Amplitude coefficient, matching the Kotlin's computeAmplitude().
        func amp(at x: CGFloat, _ sign: CGFloat) -> CGFloat {
            guard fadeFrom.isFinite else { return sign * amplitude }
            let coeff = min(max((fadeFrom + fadeLength / 2 - x) / fadeLength, 0), 1)
            return sign * amplitude * coeff
        }

        // Half-wavelength cubic segments, alternating sign — the same crest
        // construction the Kotlin canvas uses.
        let step = wavelength / 2
        var x = -phase.truncatingRemainder(dividingBy: wavelength) - step
        var sign: CGFloat = 1
        var current = amp(at: x, sign)
        path.move(to: CGPoint(x: x, y: mid + current))

        while x < rect.width {
            sign = -sign
            let nextX = x + step
            let midX = x + step / 2
            let next = amp(at: nextX, sign)
            path.addCurve(to: CGPoint(x: nextX, y: mid + next),
                          control1: CGPoint(x: midX, y: mid + current),
                          control2: CGPoint(x: midX, y: mid + next))
            current = next
            x = nextX
        }
        return path
    }
}
