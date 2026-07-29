import SwiftUI
import Combine

// MARK: - Options, mirroring the Kotlin enums one-for-one

/// Where lyric lines sit. Android's `LyricsPosition`.
enum LyricsPosition: String, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        }
    }
    /// Anchor for the glow's slight scale-up, so the line grows away from its
    /// own edge rather than drifting off-centre.
    var scaleAnchor: UnitPoint {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    var alignment: HorizontalAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
    var textAlignment: TextAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
    var frameAlignment: Alignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
}

/// Seek-bar look. Android's `SliderStyle`, where squiggly is a WAVY variant.
enum SliderStyle: String, CaseIterable, Identifiable {
    case capsule, wavy, slim
    var id: String { rawValue }

    func title(squiggly: Bool) -> String {
        switch self {
        case .capsule: "Capsule"
        case .wavy: squiggly ? "Squiggly" : "Wavy"
        case .slim: "Slim"
        }
    }
}

/// How the bottom bar marks the active tab. Android's `NavBarStyle`.
enum NavBarStyle: String, CaseIterable, Identifiable {
    case pill, gradient, underline, outlined
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pill: "Pill"
        case .gradient: "Gradient"
        case .underline: "Underline"
        case .outlined: "Outlined"
        }
    }
}

/// Grid card size. Android's `GridItemSize`.
enum GridItemSize: String, CaseIterable, Identifiable {
    case small, big
    var id: String { rawValue }
    var title: String { self == .small ? "Small" : "Big" }
    /// Card side length used by the rails and grids.
    var cardWidth: CGFloat { self == .small ? 140 : 176 }
}

/// The mini-player's shape. Android's `MiniPlayerDesign` — ids are persisted,
/// so never rename them.
enum MiniPlayerDesign: String, CaseIterable, Identifiable {
    case flat, modern, rounded, floating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .flat: "Flat"
        case .modern: "Modern"
        case .rounded: "Rounded"
        case .floating: "Floating"
        }
    }
    var subtitle: String {
        switch self {
        case .flat: "Edge-to-edge bar"
        case .modern: "Rounded pill, tap art to play"
        case .rounded: "Pill with previous / play / next"
        case .floating: "Boxy floating card"
        }
    }
    /// FLAT is the only one that doesn't tint itself from the artwork.
    var usesArtBackground: Bool { self != .flat }
}

/// What fills the mini-player behind the art. Android's `MiniPlayerBackgroundStyle`.
enum MiniPlayerBackground: String, CaseIterable, Identifiable {
    case followTheme, transparent, blur, gradient, pureBlack
    var id: String { rawValue }
    var title: String {
        switch self {
        case .followTheme: "Follow theme"
        case .transparent: "Transparent"
        case .blur: "Blur"
        case .gradient: "Gradient"
        case .pureBlack: "Pure black"
        }
    }
}

/// Which tab the app opens on. Android's `NavigationTab`, widened to our four.
enum DefaultTab: String, CaseIterable, Identifiable {
    case home, explore, yours, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .explore: "Explore"
        case .yours: "Yours"
        case .library: "Library"
        }
    }
    var tab: BlazeTab {
        switch self {
        case .home: .home
        case .explore: .explore
        case .yours: .yours
        case .library: .library
        }
    }
}

// MARK: - Store

/// Every Look & Feel preference, in one observable object so the live preview
/// and the real UI update together. Defaults match the Kotlin's.
final class LookFeel: ObservableObject {
    static let shared = LookFeel()

    @Published var lyricsPosition: LyricsPosition { didSet { save(lyricsPosition.rawValue, "lyricsPosition") } }
    @Published var sliderStyle: SliderStyle { didSet { save(sliderStyle.rawValue, "sliderStyle") } }
    @Published var squigglySlider: Bool { didSet { save(squigglySlider, "squigglySlider") } }
    @Published var navBarStyle: NavBarStyle { didSet { save(navBarStyle.rawValue, "navBarStyle") } }
    @Published var slimNavBar: Bool { didSet { save(slimNavBar, "slimNavBar") } }
    @Published var gridItemSize: GridItemSize { didSet { save(gridItemSize.rawValue, "gridItemSize") } }
    @Published var showHomeGreeting: Bool { didSet { save(showHomeGreeting, "showHomeGreeting") } }
    @Published var showHomeSearchBar: Bool { didSet { save(showHomeSearchBar, "showHomeSearchBar") } }
    @Published var defaultTab: DefaultTab { didSet { save(defaultTab.rawValue, "defaultOpenTab") } }
    @Published var miniPlayerDesign: MiniPlayerDesign { didSet { save(miniPlayerDesign.rawValue, "miniPlayerDesign") } }
    @Published var miniPlayerBackground: MiniPlayerBackground { didSet { save(miniPlayerBackground.rawValue, "miniPlayerBackground") } }
    // `playerDesign` deliberately lives only in @AppStorage("playerDesign"),
    // which the player and its picker already read — mirroring it here would
    // give us two sources of truth that drift apart.

    private let defaults = UserDefaults.standard

    private init() {
        func read<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            guard let raw = UserDefaults.standard.string(forKey: key) else { return fallback }
            return T(rawValue: raw) ?? fallback
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
        }

        lyricsPosition = read("lyricsPosition", .center)
        sliderStyle = read("sliderStyle", .slim)          // Blaze default
        squigglySlider = flag("squigglySlider", false)
        navBarStyle = read("navBarStyle", .pill)
        slimNavBar = flag("slimNavBar", false)
        gridItemSize = read("gridItemSize", .small)
        showHomeGreeting = flag("showHomeGreeting", true)
        showHomeSearchBar = flag("showHomeSearchBar", true)
        defaultTab = read("defaultOpenTab", .home)
        miniPlayerDesign = read("miniPlayerDesign", .modern)
        miniPlayerBackground = read("miniPlayerBackground", .gradient)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
