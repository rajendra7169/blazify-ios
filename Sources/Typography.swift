import SwiftUI
import UIKit

extension Font {
    /// A system font that still honours the reader's text-size setting.
    ///
    /// `Font.system(size:)` is fixed — it ignores Dynamic Type entirely, which
    /// is why the app looked identical at every accessibility size. Scaling the
    /// point size through `UIFontMetrics` keeps each call site's design intent
    /// while letting it grow.
    ///
    /// Deliberately NOT used by the phone mocks in Look & Feel or the player
    /// design gallery: those are miniature renderings of a screen, and scaling
    /// their type would push the content out of the frame.
    static func blaze(_ size: CGFloat,
                      _ weight: Font.Weight = .regular,
                      relativeTo style: UIFont.TextStyle = .body) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: size),
                weight: weight)
    }
}
