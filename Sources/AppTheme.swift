import SwiftUI

/// App-wide appearance switches, mirroring Android's PureBlackKey and
/// DynamicThemeKey. Pure black swaps the dark surfaces for true black (better
/// on OLED); dynamic theming drives accents from the album art instead of the
/// fixed Blaze amber.
final class AppTheme: ObservableObject {
    static let shared = AppTheme()

    @Published private(set) var pureBlack: Bool
    @Published private(set) var dynamicTheme: Bool

    private init() {
        pureBlack = UserDefaults.standard.object(forKey: "pureBlack") as? Bool ?? false
        dynamicTheme = UserDefaults.standard.object(forKey: "dynamicTheme") as? Bool ?? true
    }

    func setPureBlack(_ on: Bool) {
        pureBlack = on
        UserDefaults.standard.set(on, forKey: "pureBlack")
    }

    func setDynamicTheme(_ on: Bool) {
        dynamicTheme = on
        UserDefaults.standard.set(on, forKey: "dynamicTheme")
    }

    /// Page background.
    var scaffold: Color { pureBlack ? .black : Blaze.scaffold }
    /// Cards, sheets, the tab bar.
    var surface: Color { pureBlack ? Color(hex: 0x0B0B0B) : Blaze.surface }

    /// Accent to use for a given album colour — amber when dynamic theming is off.
    func accent(_ artColor: Color) -> Color { dynamicTheme ? artColor : Blaze.amber }
}
