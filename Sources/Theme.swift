import SwiftUI

/// Blazify's brand palette, ported from the Android app.
enum Blaze {
    static let amber = Color(red: 1.0, green: 0.655, blue: 0.149)   // #FFA726
    static let orange = Color(red: 1.0, green: 0.439, blue: 0.263)  // #FF7043

    static let gradient = LinearGradient(
        colors: [amber, orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing,
    )
}
