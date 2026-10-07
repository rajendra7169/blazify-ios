import SwiftUI

/// Blazify Project (C) 2026
/// Licensed under GPL-3.0

/// What the launch logo and Home's header logo tell each other, so the one can
/// land on the other and become it.
final class LaunchHandOff: ObservableObject {
    static let shared = LaunchHandOff()
    /// Where the header's logo is drawn, in screen points.
    @Published var headerLogo: CGRect?
    /// False while the launch logo is on its way, so there are never two logos at once.
    @Published var headerLogoShown = false
}

/// The launch, told as the Android app tells it. iOS shows its launch screen —
/// black, with the amber play button — and this takes over from that exact
/// frame: the flame grows round the play button, the headband sweeps over and
/// the ear cups come down, and the whole logo then glides up into Home's header
/// and becomes the logo there. It never waits on anything Home is fetching.
struct LaunchOverlay: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var handOff = LaunchHandOff.shared
    @State private var start = Date()
    /// 0 at the centre of the screen, 1 on the header's logo.
    @State private var flight: CGFloat = 0
    @State private var flying = false
    @State private var backdrop: Double = 1
    @State private var shown: Double = 1
    @State private var gone = false

    /// The canvas the launch image was drawn on, in points: it must match the
    /// launch screen's picture, which is drawn at this size in the middle.
    private let side: CGFloat = 200
    /// The build runs the loader's first half in this long.
    private let build: Double = 0.75

    var body: some View {
        if !gone {
            GeometryReader { geo in
                let screen = geo.frame(in: .global)
                ZStack {
                    Color.black.opacity(backdrop)
                    logo
                        .frame(width: size, height: size)
                        .position(centre(in: screen))
                        .opacity(shown)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(!flying)
            .task { await run() }
        }
    }

    private var logo: some View {
        TimelineView(.animation(paused: flying && flight >= 1)) { timeline in
            Canvas { gc, canvasSize in
                let elapsed = timeline.date.timeIntervalSince(start)
                // The loader's story up to the whole logo (its first half, 2 s), sped up
                // to `build`; then held whole for the flight.
                let t = CGFloat(min(elapsed / build, 1)) * 2
                let k = canvasSize.width / BlazeLogoShapes.viewSize
                gc.scaleBy(x: k, y: k)
                gc.translateBy(x: -BlazeLogoShapes.viewLeft, y: -BlazeLogoShapes.viewTop)
                LoaderStory.draw(in: &gc, t: t, colors: LoaderColors(Blaze.amber), quiet: true)
            }
        }
    }

    // The drawn logo's middle and width, as parts of the canvas: the traced logo
    // spans 170–855 by 182–772 of the 1024 box, and the canvas shows 90–934 by 110–954.
    private let logoMid = CGPoint(x: 0.5006, y: 0.4348)
    private let logoWidth: CGFloat = 0.8116
    // In the header's picture the logo spans 0.669 of the width, its middle 0.466 down.
    private let headerMid = CGPoint(x: 0.5, y: 0.466)
    private let headerWidth: CGFloat = 0.669

    private var size: CGFloat {
        guard let target = handOff.headerLogo else { return side }
        let landed = target.width * headerWidth / logoWidth
        return side + (landed - side) * flight
    }

    private func centre(in screen: CGRect) -> CGPoint {
        let from = CGPoint(x: screen.midX - screen.minX, y: screen.midY - screen.minY)
        guard let target = handOff.headerLogo else { return from }
        // Where the logo's own middle goes, then the canvas around it.
        let startMid = CGPoint(x: from.x + (logoMid.x - 0.5) * side, y: from.y + (logoMid.y - 0.5) * side)
        let endMid = CGPoint(x: target.minX + target.width * headerMid.x - screen.minX,
                             y: target.minY + target.height * headerMid.y - screen.minY)
        let mid = CGPoint(x: startMid.x + (endMid.x - startMid.x) * flight,
                          y: startMid.y + (endMid.y - startMid.y) * flight)
        return CGPoint(x: mid.x - (logoMid.x - 0.5) * size, y: mid.y - (logoMid.y - 0.5) * size)
    }

    @MainActor private func run() async {
        // The build plays out; Home lays itself out underneath meanwhile.
        try? await Task.sleep(nanoseconds: UInt64(build * 1_000_000_000))
        // The header's logo, if Home has drawn it by now (it has, unless the
        // first run's introduction is up instead).
        var waited = 0
        while handOff.headerLogo == nil, waited < 8 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waited += 1
        }
        guard handOff.headerLogo != nil else {
            // Nowhere to land: fade out where it is.
            withAnimation(.easeOut(duration: 0.3)) { backdrop = 0; shown = 0 }
            try? await Task.sleep(nanoseconds: 300_000_000)
            handOff.headerLogoShown = true
            gone = true
            return
        }
        flying = true
        withAnimation(.timingCurve(0.33, 0, 0.15, 1, duration: 0.42)) { flight = 1 }
        withAnimation(.easeOut(duration: 0.32).delay(0.04)) { backdrop = 0 }
        try? await Task.sleep(nanoseconds: 420_000_000)
        // Landed exactly on the header's logo: it fades in as this one fades out.
        handOff.headerLogoShown = true
        withAnimation(.easeOut(duration: 0.16)) { shown = 0 }
        try? await Task.sleep(nanoseconds: 180_000_000)
        gone = true
    }
}
