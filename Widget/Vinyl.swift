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

    static let amber = Color(red: 1.0, green: 0.655, blue: 0.149)   // #FFA726
    static let ember = Color(red: 1.0, green: 0.439, blue: 0.263)   // #FF7043

    /// The real logo, copied into the extension's own bundle — an app extension
    /// can't reach into the app's.
    static var logo: Image { Image(uiImage: UIImage(named: "blaze_logo_white") ?? UIImage()) }
}

/// The record: a black disc pressed with Blazify's own label.
struct VinylRecord: View {
    var diameter: CGFloat

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
                Circle()
                    .strokeBorder(.white.opacity(0.05 - Double(i) * 0.006), lineWidth: 0.6)
                    .padding(diameter * (0.055 + CGFloat(i) * 0.038))
            }

            // The lit edge that makes it sit above the paper rather than in it.
            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.8)

            brandLabel

            // Spindle hole, punched through the middle of the label.
            Circle()
                .fill(Color(white: 0.55))
                .frame(width: diameter * 0.028, height: diameter * 0.028)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.35), radius: diameter * 0.03,
                x: diameter * 0.008, y: diameter * 0.02)
    }

    /// Blazify's flame on the amber gradient — the one place on a black record
    /// where the brand can actually carry, and a real printed label rather than
    /// a placeholder standing in for artwork we can't reach.
    private var brandLabel: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Vinyl.amber, Vinyl.ember],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Vinyl.logo
                .resizable()
                .scaledToFit()
                .frame(width: label * 0.6, height: label * 0.6)
        }
        .frame(width: label, height: label)
        .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.8))
    }

    /// Pivot at the upper right, arm reaching down-left onto the record — the
    /// resting position, drawn relative to the disc so it scales with it rather
    /// than needing a size per widget family.
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
