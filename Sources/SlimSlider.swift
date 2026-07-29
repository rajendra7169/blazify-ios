import SwiftUI

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

    // Android: WavySlider rolls a broad Material wave (wavelength ~40dp,
    // 4dp stroke, bar handle); SquigglySlider a tight squiggle (waveLength 80px
    // ≈ 28dp, 3dp stroke, round thumb).
    private var amplitude: CGFloat { squiggly ? 4 : 5 }
    private var wavelength: CGFloat { squiggly ? 28 : 40 }
    private var stroke: CGFloat { squiggly ? 3 : 4 }
    private var speed: CGFloat { squiggly ? 34 : 22 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            GeometryReader { geo in
                let w = geo.size.width
                let x = w * fraction
                // Negative phase rolls the crests forward, with playback.
                let phase = isPlaying
                    ? -CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                        .truncatingRemainder(dividingBy: 10_000) * speed
                    : 0

                ZStack(alignment: .leading) {
                    // Inactive: thin flat track ahead of the thumb, with a small
                    // gap after it, as Material's wavy slider leaves.
                    Capsule().fill(Color.white.opacity(0.24))
                        .frame(width: max(w - x - 8, 0), height: 3)
                        .offset(x: min(x + 8, w))

                    // Active: the wave, settling flat while paused. The frame is
                    // tall enough that crests never get clipped vertically.
                    WavePath(amplitude: isPlaying ? amplitude : 0,
                             wavelength: wavelength, phase: phase)
                        .stroke(active, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .frame(width: max(x - 2, 0), height: amplitude * 2 + stroke + 6)
                        .clipped()

                    if squiggly {
                        // The classic squiggly slider's round thumb.
                        Circle().fill(active)
                            .frame(width: 14, height: 14)
                            .offset(x: min(max(x - 7, 0), w - 14))
                    } else {
                        // Material's bar handle.
                        RoundedRectangle(cornerRadius: 2)
                            .fill(active)
                            .frame(width: 4, height: 18)
                            .offset(x: min(max(x - 2, 0), w - 4))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isPlaying)
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

/// A rolling sine — `phase` slides the crests so the wave appears to travel.
struct WavePath: Shape {
    var amplitude: CGFloat
    var wavelength: CGFloat
    var phase: CGFloat

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY
        guard rect.width > 0 else { return path }
        path.move(to: CGPoint(x: 0, y: mid + amplitude * sin(phase / wavelength * 2 * .pi)))
        var x: CGFloat = 1
        while x <= rect.width {
            let y = mid + amplitude * sin((x + phase) / wavelength * 2 * .pi)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 1
        }
        return path
    }
}
