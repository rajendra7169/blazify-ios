import Combine
import SwiftUI

/// How the active line animates, ported from `LyricsAnimationStyle` in
/// PreferenceKeys.kt. Only applies when a provider gives word timings, and only
/// in the classic renderer — the Blazify style has its own animation.
enum LyricsAnimation: String, CaseIterable, Identifiable {
    case none, fade, glow, slide, karaoke, apple
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return String(localized: "None")
        case .fade: return String(localized: "Fade")
        case .glow: return String(localized: "Glow")
        case .slide: return String(localized: "Slide")
        case .karaoke: return String(localized: "Karaoke")
        case .apple: return String(localized: "Apple Music Style")
        }
    }
}

/// One lyrics provider, in the order Android's registry lists them.
/// Listed in Android's default priority order (LyricsProviderRegistry.kt), which
/// is also the order they're tried in. "Apple Music" is Android's "Paxsenix" —
/// same service, named for what it actually serves.
enum LyricsProvider: String, CaseIterable, Identifiable {
    case appleMusic = "Apple Music"
    case lrcLib = "LrcLib"
    case betterLyrics = "BetterLyrics"
    case youTube = "YouTube"
    case lyricsPlus = "LyricsPlus"
    case kuGou = "KuGou"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMusic: return String(localized: "Apple Music")
        case .betterLyrics: return String(localized: "Better Lyrics")
        case .lrcLib: return String(localized: "LrcLib")
        case .kuGou: return String(localized: "KuGou")
        case .youTube: return String(localized: "YouTube Music")
        case .lyricsPlus: return String(localized: "LyricsPlus")
        }
    }

    var blurb: String {
        switch self {
        case .appleMusic: return String(localized: "Word-by-word synced lyrics, the widest catalogue")
        case .betterLyrics: return String(localized: "Community aggregator, often word-level")
        case .lrcLib: return String(localized: "Open synced-lyrics database")
        case .kuGou: return String(localized: "Strong on Mandarin and Cantonese tracks")
        case .youTube: return String(localized: "Plain lyrics straight from the track page")
        case .lyricsPlus: return String(localized: "Community word-by-word database, mirrored across several servers")
        }
    }
}

/// Every lyrics preference Android exposes under Settings → Lyrics, in one
/// store. Kept apart from `LookFeel` because the Look & Feel hub only owns the
/// one setting it previews (text position).
final class LyricsPrefs: ObservableObject {
    static let shared = LyricsPrefs()

    // MARK: Sources

    @Published var enabled: [String: Bool] { didSet { saveEnabled() } }
    /// Provider names, most-preferred first.
    @Published var order: [String] { didSet { save(order, "lyricsProviderOrder") } }

    // MARK: Display

    /// Android calls this "experimental lyrics"; it's our own renderer, so it
    /// carries our name. Default on, matching `ExperimentalLyricsKey`.
    @Published var blazifyStyle: Bool { didSet { save(blazifyStyle, "blazifyLyricsStyle") } }
    @Published var glowEffect: Bool { didSet { save(glowEffect, "lyricsGlowEffect") } }
    @Published var animation: LyricsAnimation { didSet { save(animation.rawValue, "lyricsAnimationStyle") } }
    @Published var textSize: Double { didSet { save(textSize, "lyricsTextSize") } }
    @Published var lineSpacing: Double { didSet { save(lineSpacing, "lyricsLineSpacing") } }
    @Published var respectAgentPositioning: Bool { didSet { save(respectAgentPositioning, "respectAgentPositioning") } }
    @Published var clickToSeek: Bool { didSet { save(clickToSeek, "lyricsClick") } }
    @Published var autoScroll: Bool { didSet { save(autoScroll, "lyricsScrollKey") } }
    @Published var hideStatusBarFullscreen: Bool { didSet { save(hideStatusBarFullscreen, "hideStatusBarOnFullscreen") } }

    // Android's defaults, from LyricsSettings.kt's reset buttons.
    static let defaultTextSize: Double = 24
    static let defaultLineSpacing: Double = 1.3
    static let textSizeRange: ClosedRange<Double> = 12...48
    static let lineSpacingRange: ClosedRange<Double> = 1.0...3.0

    private init() {
        let d = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) as? Bool ?? fallback
        }
        func number(_ key: String, _ fallback: Double) -> Double {
            d.object(forKey: key) as? Double ?? fallback
        }

        var on: [String: Bool] = [:]
        for provider in LyricsProvider.allCases {
            on[provider.rawValue] = flag("lyricsEnabled_\(provider.rawValue)", true)
        }
        enabled = on
        let stored = d.stringArray(forKey: "lyricsProviderOrder") ?? []
        // Keep any provider the stored order doesn't mention — a new provider
        // must not silently vanish because an old order was saved.
        let known = LyricsProvider.allCases.map(\.rawValue)
        order = stored.filter(known.contains) + known.filter { !stored.contains($0) }

        blazifyStyle = flag("blazifyLyricsStyle", true)
        glowEffect = flag("lyricsGlowEffect", true)
        animation = LyricsAnimation(rawValue: d.string(forKey: "lyricsAnimationStyle") ?? "")
            ?? .apple
        textSize = number("lyricsTextSize", Self.defaultTextSize)
        lineSpacing = number("lyricsLineSpacing", Self.defaultLineSpacing)
        respectAgentPositioning = flag("respectAgentPositioning", true)
        clickToSeek = flag("lyricsClick", true)
        autoScroll = flag("lyricsScrollKey", true)
        hideStatusBarFullscreen = flag("hideStatusBarOnFullscreen", false)
    }

    // MARK: Queries used by the fetcher

    func isEnabled(_ provider: LyricsProvider) -> Bool { enabled[provider.rawValue] ?? true }

    /// Providers in preference order, skipping the disabled ones. Never empty:
    /// turning everything off would leave no lyrics at all, so the first
    /// provider stays in as a floor.
    var activeOrder: [LyricsProvider] {
        let active = order.compactMap(LyricsProvider.init(rawValue:))
            .filter { isEnabled($0) }
        return active.isEmpty ? [.appleMusic] : active
    }

    /// Rank for sorting candidates — lower is better; unknown providers last.
    func rank(of providerName: String) -> Int {
        let names = activeOrder.map { $0.rawValue.lowercased() }
        return names.firstIndex(of: providerName.lowercased()) ?? names.count
    }

    /// A value copy for the lyrics fan-out, which runs off the main actor.
    @MainActor
    func snapshot() -> Lyrics.ProviderPrefs {
        Lyrics.ProviderPrefs(active: activeOrder.map(\.rawValue))
    }

    func resetDisplay() {
        textSize = Self.defaultTextSize
        lineSpacing = Self.defaultLineSpacing
    }

    // MARK: Storage

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func saveEnabled() {
        for (name, on) in enabled {
            UserDefaults.standard.set(on, forKey: "lyricsEnabled_\(name)")
        }
    }
}
