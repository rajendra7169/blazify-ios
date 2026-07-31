import SwiftUI

/// The widget's palette. Blazify's own amber-on-black rather than anything
/// invented for the Home Screen — with the turntable gone, a shortcut panel
/// that doesn't look like the app it opens is just confusing.
enum Sleeve {
    static func paper(_ dark: Bool) -> Color {
        dark ? Color(red: 0.04, green: 0.04, blue: 0.05)      // near-black
             : Color(red: 1.0, green: 0.99, blue: 0.98)
    }
    static func tile(_ dark: Bool) -> Color {
        dark ? Color(red: 0.10, green: 0.10, blue: 0.12)
             : Color(red: 0.96, green: 0.95, blue: 0.94)
    }
    static func ink(_ dark: Bool) -> Color {
        dark ? .white : Color(red: 0.10, green: 0.08, blue: 0.07)
    }

    static let amber = Color(red: 1.0, green: 0.655, blue: 0.149)   // #FFA726
    static let ember = Color(red: 1.0, green: 0.439, blue: 0.263)   // #FF7043

    static var gradient: LinearGradient {
        LinearGradient(colors: [amber, ember], startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }

    /// The real logo, copied into the extension's own bundle — an app extension
    /// can't reach into the app's.
    static var logo: Image { Image(uiImage: UIImage(named: "blaze_logo_white") ?? UIImage()) }
}

/// Logo plate and wordmark, so the widget says whose it is at a glance.
struct SleeveHeader: View {
    var dark: Bool
    var size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.34) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Sleeve.gradient)
                Sleeve.logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.62, height: size * 0.62)
            }
            .frame(width: size, height: size)

            Text("Blazify")
                .font(.system(size: size * 0.68, weight: .bold))
                .foregroundStyle(Sleeve.ink(dark))
                .lineLimit(1)
        }
    }
}

/// One shortcut. The whole tile is the tap target, not just the glyph.
struct SleeveTile: View {
    var symbol: String
    var title: LocalizedStringKey
    var url: URL
    var dark: Bool
    var icon: CGFloat
    var label: CGFloat

    var body: some View {
        Link(destination: url) {
            VStack(spacing: icon * 0.28) {
                Image(systemName: symbol)
                    .font(.system(size: icon, weight: .semibold))
                    .foregroundStyle(Sleeve.amber)
                Text(title)
                    .font(.system(size: label, weight: .semibold))
                    .foregroundStyle(Sleeve.ink(dark))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Sleeve.tile(dark))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
