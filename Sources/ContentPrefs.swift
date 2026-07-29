import Combine
import SwiftUI

/// Settings → Content, ported from `ContentSettings.kt`. The language and
/// country here are the `hl` / `gl` every InnerTube request carries, so changing
/// them really does change what YouTube returns.
final class ContentPrefs: ObservableObject {
    static let shared = ContentPrefs()

    @Published var language: String { didSet { save(language, "contentLanguage") } }
    @Published var country: String { didSet { save(country, "contentCountry") } }

    @Published var hideExplicit: Bool { didSet { save(hideExplicit, "hideExplicit") } }
    @Published var hideVideoSongs: Bool { didSet { save(hideVideoSongs, "hideVideoSongs") } }

    @Published var showArtistDescription: Bool { didSet { save(showArtistDescription, "showArtistDescription") } }
    @Published var showMonthlyListeners: Bool { didSet { save(showMonthlyListeners, "showArtistMonthlyListeners") } }
    @Published var showSubscriberCount: Bool { didSet { save(showSubscriberCount, "showArtistSubscriberCount") } }

    @Published var randomizeHomeOrder: Bool { didSet { save(randomizeHomeOrder, "randomizeHomeOrder") } }
    @Published var showStatsPlaylists: Bool { didSet { save(showStatsPlaylists, "showMostStatsPlaylists") } }

    /// The languages and regions YouTube Music actually serves, kept short —
    /// the full ISO list would be a wall of rows nobody scrolls.
    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("ne", "Nepali"), ("hi", "Hindi"), ("es", "Spanish"),
        ("fr", "French"), ("de", "German"), ("pt", "Portuguese"), ("ru", "Russian"),
        ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("ar", "Arabic"),
        ("id", "Indonesian"), ("tr", "Turkish"), ("it", "Italian"),
    ]
    static let countries: [(code: String, name: String)] = [
        ("US", "United States"), ("NP", "Nepal"), ("IN", "India"), ("GB", "United Kingdom"),
        ("CA", "Canada"), ("AU", "Australia"), ("DE", "Germany"), ("FR", "France"),
        ("BR", "Brazil"), ("JP", "Japan"), ("KR", "South Korea"), ("ID", "Indonesia"),
        ("MX", "Mexico"), ("RU", "Russia"), ("ZA", "South Africa"),
    ]

    static func name(ofLanguage code: String) -> String {
        languages.first { $0.code == code }?.name ?? code
    }
    static func name(ofCountry code: String) -> String {
        countries.first { $0.code == code }?.name ?? code
    }

    private init() {
        let d = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }

        // Default to the device's own language and region rather than forcing
        // en/US on someone in Kathmandu.
        let deviceLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let deviceRegion = Locale.current.region?.identifier ?? "US"
        language = d.string(forKey: "contentLanguage")
            ?? (Self.languages.contains { $0.code == deviceLanguage } ? deviceLanguage : "en")
        country = d.string(forKey: "contentCountry")
            ?? (Self.countries.contains { $0.code == deviceRegion } ? deviceRegion : "US")

        hideExplicit = flag("hideExplicit", false)
        hideVideoSongs = flag("hideVideoSongs", false)
        showArtistDescription = flag("showArtistDescription", true)
        showMonthlyListeners = flag("showArtistMonthlyListeners", true)
        showSubscriberCount = flag("showArtistSubscriberCount", true)
        randomizeHomeOrder = flag("randomizeHomeOrder", true)
        showStatsPlaylists = flag("showMostStatsPlaylists", true)
    }

    /// Applies the Hide-explicit and Hide-video-songs filters. Read straight
    /// from defaults so the concurrent parsers can call it off the main actor.
    static func allows(_ track: Track) -> Bool {
        let d = UserDefaults.standard
        if d.bool(forKey: "hideExplicit"), track.isExplicit { return false }
        if d.bool(forKey: "hideVideoSongs"), track.isVideo { return false }
        return true
    }

    static func filtered(_ tracks: [Track]) -> [Track] { tracks.filter(allows) }

    /// Read off the main actor by the request builders, which run concurrently.
    static var locale: (hl: String, gl: String) {
        let d = UserDefaults.standard
        return (d.string(forKey: "contentLanguage") ?? "en",
                d.string(forKey: "contentCountry") ?? "US")
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
