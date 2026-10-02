import SwiftUI

/// Blazify Project (C) 2026
/// Licensed under GPL-3.0

/// Three bars that dance while a song plays.
///
/// A still symbol on the artwork says "this is the one", which the highlight
/// behind the row already said. What it cannot say is whether the song is
/// actually playing or sitting paused — and in a list of fifty rows that is the
/// one thing somebody is looking for. Movement says it without a word.
///
/// Driven by the clock rather than by a timer of its own: each bar is a sine
/// wave at its own speed, so nothing has to be scheduled, nothing is left
/// running when the view goes away, and the three never fall into step with each
/// other and start looking mechanical.
struct PlayingBars: View {
    var color: Color = .white
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    var height: CGFloat = 18

    /// Deliberately not round numbers: speeds that share a factor drift into
    /// unison after a few seconds and the dance turns into a salute.
    private let speeds: [Double] = [3.1, 4.7, 2.3]
    private let phases: [Double] = [0, 1.3, 2.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0 ..< 3, id: \.self) { bar in
                    // Never all the way down: a bar at zero height reads as a
                    // gap in the row rather than as a quiet moment.
                    let wave = (sin(t * speeds[bar] + phases[bar]) + 1) / 2
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: max(0.2, wave) * height)
                }
            }
            .frame(height: height, alignment: .bottom)
        }
    }
}
