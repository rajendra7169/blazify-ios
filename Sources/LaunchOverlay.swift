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
    @Published var headerLogoShown = true
}
