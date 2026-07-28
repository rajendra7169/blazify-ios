import SwiftUI
import UIKit

enum DarkMode: String, CaseIterable {
    case auto, on, off

    var title: String {
        switch self {
        case .auto: "Auto"
        case .on: "Dark"
        case .off: "Light"
        }
    }
}

/// App-wide appearance, mirroring Android's DynamicThemeKey / DarkModeKey /
/// PureBlackKey.
///
/// Android derives a whole Material scheme from one seed colour using HCT tonal
/// palettes. We do the same shape — a low-chroma neutral ramp for surfaces and a
/// higher-chroma ramp for the accent — approximated in HSB, which lands very
/// close for the dark scheme this app actually ships.
final class AppTheme: ObservableObject {
    static let shared = AppTheme()

    @Published private(set) var pureBlack: Bool
    @Published private(set) var dynamicTheme: Bool
    @Published private(set) var darkMode: DarkMode
    /// The seed: album art when dynamic, otherwise the chosen palette colour.
    @Published private(set) var seed: Color

    /// Set by the player as artwork changes.
    private var artSeed: Color?
    private var chosenSeed: Color

    private init() {
        pureBlack = UserDefaults.standard.object(forKey: "pureBlack") as? Bool ?? false
        dynamicTheme = UserDefaults.standard.object(forKey: "dynamicTheme") as? Bool ?? true
        darkMode = DarkMode(rawValue: UserDefaults.standard.string(forKey: "darkMode") ?? "") ?? .auto
        let saved = UserDefaults.standard.object(forKey: "seedColor") as? Int
        chosenSeed = saved.map { Color(hex: UInt($0)) } ?? Blaze.amber
        seed = chosenSeed
    }

    // MARK: Settings

    func setPureBlack(_ on: Bool) {
        pureBlack = on
        UserDefaults.standard.set(on, forKey: "pureBlack")
    }

    func setDynamicTheme(_ on: Bool) {
        dynamicTheme = on
        UserDefaults.standard.set(on, forKey: "dynamicTheme")
        recomputeSeed()
    }

    func setDarkMode(_ mode: DarkMode) {
        darkMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "darkMode")
    }

    func setSeedColor(_ color: Color) {
        chosenSeed = color
        UserDefaults.standard.set(Int(color.rgbHex), forKey: "seedColor")
        recomputeSeed()
    }

    /// The player pushes the artwork colour here.
    func setArtworkSeed(_ color: Color?) {
        artSeed = color
        recomputeSeed()
    }

    private func recomputeSeed() {
        let next = (dynamicTheme ? artSeed : nil) ?? chosenSeed
        if next != seed { seed = next }
    }

    // MARK: Resolved scheme

    /// Whether we're rendering dark. `.auto` follows the system.
    func isDark(_ scheme: ColorScheme) -> Bool {
        switch darkMode {
        case .auto: scheme == .dark
        case .on: true
        case .off: false
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch darkMode {
        case .auto: nil
        case .on: .dark
        case .off: .light
        }
    }

    /// Resolved dark/light without a view context, so plain `theme.surface`
    /// call sites keep working.
    var resolvedDark: Bool {
        switch darkMode {
        case .auto: UITraitCollection.current.userInterfaceStyle == .dark
        case .on: true
        case .off: false
        }
    }

    var scaffold: Color { scaffold(resolvedDark) }
    var surface: Color { surface(resolvedDark) }
    var surfaceHigh: Color { surfaceHigh(resolvedDark) }
    var accent: Color { accent(resolvedDark) }
    var onSurface: Color { onSurface(resolvedDark) }
    var onSurfaceVariant: Color { onSurfaceVariant(resolvedDark) }

    // Tonal ramps. Tones follow the Material 2025 spec values Android uses.

    /// Page background — tone 4 dark / 98 light, black when pure black.
    func scaffold(_ dark: Bool) -> Color {
        if dark && pureBlack { return .black }
        return dark ? seed.tone(4, chroma: 0.06) : seed.tone(98, chroma: 0.02)
    }

    /// Cards, sheets, the tab bar — tone 9 dark / 94 light.
    func surface(_ dark: Bool) -> Color {
        if dark && pureBlack { return Color(hex: 0x0A0A0A) }
        return dark ? seed.tone(9, chroma: 0.08) : seed.tone(94, chroma: 0.03)
    }

    /// A step above `surface` — tone 12 dark / 92 light.
    func surfaceHigh(_ dark: Bool) -> Color {
        if dark && pureBlack { return Color(hex: 0x121212) }
        return dark ? seed.tone(12, chroma: 0.10) : seed.tone(92, chroma: 0.04)
    }

    /// The accent — tone 80 dark / 40 light, as Material does.
    func accent(_ dark: Bool) -> Color {
        dark ? seed.tone(80, chroma: 0.62) : seed.tone(40, chroma: 0.70)
    }

    func onSurface(_ dark: Bool) -> Color { dark ? .white : Color(hex: 0x1A1A1A) }
    func onSurfaceVariant(_ dark: Bool) -> Color {
        dark ? .white.opacity(0.68) : Color(hex: 0x1A1A1A).opacity(0.62)
    }
}

extension Color {
    /// A tone of this colour: `tone` is Material's L* 0…100, `chroma` scales
    /// saturation. Approximates a tonal-palette lookup in HSB.
    func tone(_ tone: Double, chroma: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let brightness = max(0, min(1, tone / 100))
        // Dark tones need a touch more saturation to keep the seed readable.
        let sat = min(1, max(0, s * chroma * (tone < 50 ? 1.25 : 1.0)))
        return Color(hue: Double(h), saturation: Double(sat), brightness: brightness)
    }

    /// 0xRRGGBB for persistence.
    var rgbHex: UInt {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt(r * 255) << 16) | (UInt(g * 255) << 8) | UInt(b * 255)
    }
}

/// The resolved palette for the current appearance.
///
/// Colours are *stored*, not computed on demand, so the value genuinely changes
/// when the seed changes — that's what makes SwiftUI repaint every view when
/// new album art recolours the app. A version that read `AppTheme.shared`
/// lazily would compare equal and nothing downstream would redraw.
struct Palette: Equatable {
    let dark: Bool
    let scaffold: Color
    let surface: Color
    let surfaceHigh: Color
    let accent: Color
    let onSurface: Color
    let onSurfaceVariant: Color
    /// Text/icons drawn on top of `accent`.
    let onAccent: Color

    init(dark: Bool, theme: AppTheme = .shared) {
        self.dark = dark
        scaffold = theme.scaffold(dark)
        surface = theme.surface(dark)
        surfaceHigh = theme.surfaceHigh(dark)
        accent = theme.accent(dark)
        onSurface = theme.onSurface(dark)
        onSurfaceVariant = theme.onSurfaceVariant(dark)
        onAccent = dark ? theme.seed.tone(20, chroma: 0.5) : .white
    }

    /// The greeting-card / hero gradient, seeded by the current accent so it
    /// tracks album art the way Android's `colorScheme.primary` does.
    var heroGradient: LinearGradient {
        LinearGradient(colors: [accent, accent.tone(dark ? 55 : 48, chroma: 0.95)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Divider / hairline colour.
    var separator: Color { onSurface.opacity(0.08) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(dark: true)
}

/// Height taken by the mini-player + tab bar, so scrolling content can clear
/// them — the equivalent of Android's `LocalPlayerAwareWindowInsets`.
private struct PlayerInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    var playerBottomInset: CGFloat {
        get { self[PlayerInsetKey.self] }
        set { self[PlayerInsetKey.self] = newValue }
    }
}

extension View {
    /// Clears the mini-player and tab bar at the end of a scrolling page.
    func playerAwareBottomPadding(_ inset: CGFloat, extra: CGFloat = 12) -> some View {
        padding(.bottom, inset + extra)
    }
}
