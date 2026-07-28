import SwiftUI

/// Blaze's default SLIM (Apple-Music-style) seek bar: an 8pt round-capped track,
/// no visible thumb, inactive white@24%, active = the song's dynamic color.
struct SlimSlider: View {
    @Binding var value: Double        // 0...1
    let active: Color
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Never let the fill get narrower than it is tall: below that a
            // Capsule squashes into a sliver with a flat left edge instead of
            // sitting rounded inside the track.
            let filled = min(max(w * value, 8), w)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.24))
                    .frame(height: 8)
                Capsule().fill(active)
                    .frame(width: filled, height: 8)
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
