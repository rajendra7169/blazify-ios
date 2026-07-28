import SwiftUI

/// The seek bar, in whichever style Look & Feel selects: SLIM (Apple-Music
/// style, the Blaze default), CAPSULE (thicker), or WAVY — which draws a sine
/// over the played portion, tighter and taller when squiggly is on.
struct SlimSlider: View {
    @Binding var value: Double        // 0...1
    let active: Color
    let onCommit: (Double) -> Void

    @ObservedObject private var look = LookFeel.shared

    private var trackHeight: CGFloat {
        switch look.sliderStyle {
        case .slim: 8
        case .capsule: 12
        case .wavy: 4
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Never let the fill get narrower than it is tall: below that a
            // Capsule squashes into a sliver with a flat left edge instead of
            // sitting rounded inside the track.
            let filled = min(max(w * value, trackHeight), w)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.24))
                    .frame(height: trackHeight)
                if look.sliderStyle == .wavy {
                    Wave(amplitude: look.squigglySlider ? 7 : 4,
                         wavelength: look.squigglySlider ? 16 : 30)
                        .stroke(active, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: filled, height: 20)
                } else {
                    Capsule().fill(active)
                        .frame(width: filled, height: trackHeight)
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
        .frame(height: 24)
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
}
