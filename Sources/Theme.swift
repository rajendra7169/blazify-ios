import SwiftUI
import UIKit

extension Image {
    /// Loads a loose bundle PNG (brand art ships as resources, not an asset
    /// catalog, so Xcode's actool never touches it — see build history).
    init(bundleImage name: String) {
        self = Image(uiImage: UIImage(named: name) ?? UIImage())
    }
}

/// Blazify's brand palette, ported from the BlazePlayer (Flutter) design reference.
enum Blaze {
    static let amber = Color(hex: 0xFFA726)   // primary accent
    static let orange = Color(hex: 0xFF7043)  // light-mode accent / gradient end
    static let amberDeep = Color(hex: 0xFF8F00) // dark-mode card gradient end

    static let scaffold = Color(hex: 0x121212)  // home background
    static let surface = Color(hex: 0x1E1E1E)   // nav bar / cards / sheets

    /// Header wordmark / pill accents (amber → deep orange).
    static let gradient = LinearGradient(
        colors: [amber, orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing,
    )

    /// Dark-mode greeting card gradient (amber → darker orange), matching Flutter.
    static let cardGradient = LinearGradient(
        colors: [amber, amberDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing,
    )
}

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
        )
    }
}
