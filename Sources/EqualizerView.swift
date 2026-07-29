import SwiftUI

/// Settings → Equaliser. A draggable ten-band curve over a live level display,
/// preset chips, bass and width, and a headroom readout so it's obvious what
/// the preamp is doing rather than leaving you to wonder why it got quieter.
struct EqualizerView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var eq = Equalizer.shared
    @ObservedObject var player: Player

    var body: some View {
        SettingsPage(title: "Equaliser") {
            SettingsGroup(title: "Equaliser") {
                SettingsToggle(symbol: "slider.horizontal.3", title: "Enable",
                               subtitle: "Off leaves the audio completely untouched",
                               isOn: $eq.enabled)
            }

            curveCard
                .opacity(eq.enabled ? 1 : 0.4)
                .allowsHitTesting(eq.enabled)

            presets
                .opacity(eq.enabled ? 1 : 0.4)
                .allowsHitTesting(eq.enabled)

            SettingsGroup(title: "Tone") {
                SettingsSlider(symbol: "waveform.path", title: "Bass",
                               value: $eq.bass, range: Equalizer.bassRange, step: 0.5) {
                    $0 == 0 ? "Off" : String(format: "+%.1f dB", $0)
                }
                SettingsDivider()
                SettingsSlider(symbol: "arrow.left.and.right", title: "Stereo width",
                               value: $eq.width, range: Equalizer.widthRange, step: 0.05) {
                    $0 <= 1.001 ? "Normal" : String(format: "%.0f%% wider", ($0 - 1) * 100)
                }
            }
            .opacity(eq.enabled ? 1 : 0.4)
            .allowsHitTesting(eq.enabled)

            SettingsGroup(title: "Reset") {
                SettingsLink(symbol: "arrow.counterclockwise", title: "Reset to flat",
                             subtitle: "Clears every band, bass and width") { eq.reset() }
            }

            Text("Boosting a band pulls the preamp down by the same amount, so "
                 + "the loudest point never rises above where it started. That's "
                 + "why heavy bass here changes the tone instead of distorting.")
                .font(.system(size: 12))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, 6)
        }
    }

    // MARK: The curve

    private var curveCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("−12 dB   ·   +12 dB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant)
                Spacer()
                Text(eq.headroom < 0
                     ? String(format: "Preamp %.1f dB", eq.headroom)
                     : "No preamp needed")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(eq.headroom < -6 ? .orange : palette.onSurfaceVariant)
            }

            EQCurve(eq: eq, accent: palette.accent,
                    ink: palette.onSurface, playing: player.isPlaying)
                .frame(height: 190)

            HStack(spacing: 0) {
                ForEach(Array(EqualizerDSP.frequencies.enumerated()), id: \.offset) { _, hz in
                    Text(hz >= 1000 ? "\(Int(hz / 1000))k" : "\(Int(hz))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EQPreset.allCases) { preset in
                    let active = preset == eq.preset
                    Text(preset.title)
                        .font(.system(size: 13, weight: active ? .bold : .medium))
                        .foregroundStyle(active ? palette.onAccent : palette.onSurfaceVariant)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(active ? AnyShapeStyle(palette.accent)
                                           : AnyShapeStyle(palette.surfaceHigh))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { eq.preset = preset }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

/// The interactive curve: bars for the live level behind, a filled spline for
/// the response, and a draggable handle per band.
struct EQCurve: View {
    @ObservedObject var eq: Equalizer
    let accent: Color
    let ink: Color
    let playing: Bool

    @State private var levels = [Float](repeating: 0, count: EqualizerDSP.bandCount)

    private let range = Equalizer.gainRange

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step = w / CGFloat(EqualizerDSP.bandCount)

            ZStack(alignment: .topLeading) {
                // Level bars, drawn behind everything as atmosphere.
                HStack(spacing: 0) {
                    ForEach(0..<EqualizerDSP.bandCount, id: \.self) { i in
                        let level = CGFloat(levels[i])
                        RoundedRectangle(cornerRadius: 3)
                            .fill(accent.opacity(0.16))
                            .frame(width: step * 0.42, height: max(4, h * level))
                            .frame(width: step, height: h, alignment: .bottom)
                    }
                }

                // Zero line.
                Rectangle()
                    .fill(ink.opacity(0.12))
                    .frame(height: 1)
                    .offset(y: h / 2)

                // The response curve, filled to the zero line.
                curvePath(width: w, height: h, step: step)
                    .fill(LinearGradient(colors: [accent.opacity(0.35), accent.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                curveLine(width: w, height: h, step: step)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round,
                                                       lineJoin: .round))

                // A handle per band.
                ForEach(0..<EqualizerDSP.bandCount, id: \.self) { i in
                    let x = step * (CGFloat(i) + 0.5)
                    let y = yFor(eq.bands[i], height: h)
                    Circle()
                        .fill(accent)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                        .shadow(color: accent.opacity(0.5), radius: 5)
                        .position(x: x, y: y)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    eq.markCustom()
                                    eq.bands[i] = gainFor(value.location.y, height: h)
                                }
                        )
                }
            }
            .contentShape(Rectangle())
            // Drag anywhere to shape the nearest band, not just on the handle.
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let i = min(max(Int(value.location.x / step), 0),
                                    EqualizerDSP.bandCount - 1)
                        eq.markCustom()
                        eq.bands[i] = gainFor(value.location.y, height: h)
                    }
            )
        }
        // Poll the analyser rather than publishing from the audio thread, which
        // must never touch SwiftUI.
        .onReceive(Timer.publish(every: 1.0 / 20, on: .main, in: .common).autoconnect()) { _ in
            guard playing, eq.enabled else {
                if levels.contains(where: { $0 > 0.01 }) {
                    levels = levels.map { $0 * 0.8 }
                }
                return
            }
            levels = EqualizerDSP.shared.spectrum
        }
    }

    private func yFor(_ gain: Double, height: CGFloat) -> CGFloat {
        let t = (gain - range.lowerBound) / (range.upperBound - range.lowerBound)
        return height * (1 - CGFloat(t))
    }

    private func gainFor(_ y: CGFloat, height: CGFloat) -> Double {
        let t = 1 - min(max(y / max(height, 1), 0), 1)
        let raw = range.lowerBound + Double(t) * (range.upperBound - range.lowerBound)
        // Snap to half a dB — fine enough to be expressive, coarse enough that
        // a value you set is a value you can set again.
        return (raw * 2).rounded() / 2
    }

    private func points(width: CGFloat, height: CGFloat, step: CGFloat) -> [CGPoint] {
        (0..<EqualizerDSP.bandCount).map { i in
            CGPoint(x: step * (CGFloat(i) + 0.5), y: yFor(eq.bands[i], height: height))
        }
    }

    private func curveLine(width: CGFloat, height: CGFloat, step: CGFloat) -> Path {
        var path = Path()
        let pts = points(width: width, height: height, step: step)
        guard let first = pts.first else { return path }
        path.move(to: CGPoint(x: 0, y: first.y))
        path.addLine(to: first)
        for i in 1..<pts.count {
            let prev = pts[i - 1], next = pts[i]
            let midX = (prev.x + next.x) / 2
            path.addCurve(to: next, control1: CGPoint(x: midX, y: prev.y),
                          control2: CGPoint(x: midX, y: next.y))
        }
        path.addLine(to: CGPoint(x: width, y: pts[pts.count - 1].y))
        return path
    }

    private func curvePath(width: CGFloat, height: CGFloat, step: CGFloat) -> Path {
        var path = curveLine(width: width, height: height, step: step)
        path.addLine(to: CGPoint(x: width, y: height / 2))
        path.addLine(to: CGPoint(x: 0, y: height / 2))
        path.closeSubpath()
        return path
    }
}
