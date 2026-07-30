import SwiftUI

/// The turntable's palette. Warm paper and roasted browns rather than Blazify's
/// amber-on-black: a widget sits on the user's own wallpaper, and the record
/// sleeve look is what makes it read as a record player instead of a control
/// panel. Both schemes are authored — a cream card at 2am is a torch.
enum Vinyl {
    static func paper(_ dark: Bool) -> Color {
        dark ? Color(red: 0.09, green: 0.07, blue: 0.06)      // #171210
             : Color(red: 0.949, green: 0.902, blue: 0.796)   // #F2E6CB
    }
    static func ink(_ dark: Bool) -> Color {
        dark ? Color(red: 0.949, green: 0.902, blue: 0.796)
             : Color(red: 0.243, green: 0.137, blue: 0.09)    // #3E2317
    }
    static func muted(_ dark: Bool) -> Color {
        dark ? Color(red: 0.725, green: 0.6, blue: 0.494)     // #B9997E
             : Color(red: 0.545, green: 0.42, blue: 0.325)    // #8B6B53
    }
    static func rail(_ dark: Bool) -> Color {
        dark ? Color(red: 0.2, green: 0.165, blue: 0.133)     // #332A22
             : Color(red: 0.886, green: 0.831, blue: 0.706)   // #E2D4B4
    }
    /// The arm and its pivot — cool grey against all that warmth, which is what
    /// makes it read as hardware sitting on top rather than part of the print.
    static let arm = Color(red: 0.855, green: 0.855, blue: 0.875)
    static let pivot = Color(red: 0.302, green: 0.263, blue: 0.318)
}

/// The record: a black disc with the artwork as its label, under a tonearm.
struct VinylRecord: View {
    var artwork: Image?
    var diameter: CGFloat
    /// Records spin. This one leans a few degrees per song so two songs in a
    /// row never look like a frozen screenshot, without animating a widget
    /// (which can't animate) or spending reloads pretending to.
    var angle: Double = 0

    private var label: CGFloat { diameter * 0.46 }

    var body: some View {
        ZStack {
            disc
            tonearm
        }
        .frame(width: diameter, height: diameter)
    }

    private var disc: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(white: 0.16), Color(white: 0.055), .black],
                    center: .init(x: 0.38, y: 0.32),
                    startRadius: 0, endRadius: diameter * 0.62))

            // Grooves. Six rings at falling opacity read as pressed vinyl;
            // more than that turns to moiré at widget scale.
            ForEach(0..<6, id: \.self) { i in
                let t = CGFloat(i)
                Circle()
                    .strokeBorder(.white.opacity(0.05 - Double(i) * 0.006),
                                  lineWidth: 0.6)
                    .padding(diameter * (0.055 + t * 0.038))
            }

            // The lit edge that makes it sit above the paper rather than in it.
            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.8)

            artLabel
                .rotationEffect(.degrees(angle))

            // Spindle hole, punched in the paper colour so it looks through.
            Circle()
                .fill(Color(white: 0.55))
                .frame(width: diameter * 0.028, height: diameter * 0.028)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.35), radius: diameter * 0.03,
                x: diameter * 0.008, y: diameter * 0.02)
    }

    @ViewBuilder private var artLabel: some View {
        ZStack {
            if let artwork {
                artwork
                    .resizable()
                    .scaledToFill()
            } else {
                // No art yet — a warm plate with the flame, rather than a grey
                // hole where the song should be.
                LinearGradient(colors: [Color(red: 1.0, green: 0.655, blue: 0.149),
                                        Color(red: 1.0, green: 0.439, blue: 0.263)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "flame.fill")
                    .font(.system(size: label * 0.34, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: label, height: label)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.8))
    }

    /// Pivot at the upper right, arm reaching down-left onto the record — the
    /// resting position, drawn in the widget's own coordinate space so it
    /// scales with the disc instead of needing a size per family.
    private var tonearm: some View {
        ZStack {
            Capsule()
                .fill(Vinyl.arm)
                .frame(width: diameter * 0.045, height: diameter * 0.44)
                .overlay(Capsule().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                .rotationEffect(.degrees(28))
                .offset(x: diameter * 0.30, y: diameter * 0.06)

            // Headshell, the block that carries the needle.
            RoundedRectangle(cornerRadius: diameter * 0.018, style: .continuous)
                .fill(Vinyl.arm)
                .frame(width: diameter * 0.07, height: diameter * 0.085)
                .rotationEffect(.degrees(28))
                .offset(x: diameter * 0.19, y: diameter * 0.26)

            // Pivot: the post, then the counterweight cap on top of it.
            Capsule()
                .fill(Vinyl.pivot)
                .frame(width: diameter * 0.11, height: diameter * 0.17)
                .offset(x: diameter * 0.40, y: -diameter * 0.10)
            Circle()
                .fill(Vinyl.arm)
                .frame(width: diameter * 0.085, height: diameter * 0.085)
                .offset(x: diameter * 0.40, y: -diameter * 0.165)
        }
        .shadow(color: .black.opacity(0.2), radius: diameter * 0.012, y: diameter * 0.008)
    }
}

/// The bar under the title. Flat capsules, no shading — the record is the
/// ornament here and a glossy progress bar would compete with it.
struct VinylProgress: View {
    var fraction: Double
    var dark: Bool

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Vinyl.rail(dark))
                Capsule()
                    .fill(Vinyl.ink(dark).opacity(dark ? 0.85 : 0.7))
                    .frame(width: max(g.size.width * min(max(fraction, 0), 1), 2))
            }
        }
        .frame(height: 5)
    }
}
