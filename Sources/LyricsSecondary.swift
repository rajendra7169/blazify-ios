import Foundation
import SwiftUI

/// The second line shown under each lyric — a romanisation or a translation.
/// Both go through here so the pane measures and draws them one way, which
/// matters: line positions come from the measured height of each row, so a
/// second line that isn't accounted for would misplace every lyric below it.
final class LyricsSecondary: ObservableObject {
    static let shared = LyricsSecondary()

    /// videoId → line index → the extra line.
    @Published private(set) var lines: [String: [Int: String]] = [:]
    @Published private(set) var working = false

    private var inFlight: Set<String> = []

    private init() {}

    func text(for videoId: String, line: Int) -> String? {
        lines[videoId]?[line]
    }

    func clear() {
        lines.removeAll()
        inFlight.removeAll()
    }

    /// Fill in the secondary lines for a song, once. Romanisation is local and
    /// instant; translation goes out to whichever provider is configured, and
    /// costs money per call, so both are cached per song and never recomputed
    /// from a view body.
    func prepare(videoId: String, lyrics: [LyricLine]) {
        guard !videoId.isEmpty, !lyrics.isEmpty else { return }
        let romanize = RomanizePrefs.shared
        let translate = AIPrefs.shared

        // Romanisation wins when both are on: seeing the sounds AND a
        // translation stacked under one line is unreadable.
        if romanize.enabled, romanize.applies(to: lyrics) {
            let key = "rom:\(videoId)"
            guard !inFlight.contains(key), lines[videoId] == nil else { return }
            inFlight.insert(key)
            var out: [Int: String] = [:]
            for (i, line) in lyrics.enumerated() {
                if let latin = Romanize.toLatin(line.text), latin != line.text {
                    out[i] = latin
                }
            }
            lines[videoId] = out
            inFlight.remove(key)
            return
        }

        guard translate.isConfigured else { return }
        let key = "ai:\(videoId)"
        guard !inFlight.contains(key), lines[videoId] == nil else { return }
        inFlight.insert(key)
        working = true

        // Strong self: this is a singleton that lives for the app's lifetime,
        // and a weak capture read back inside the main-actor hop is exactly the
        // pattern Swift 6 rejects.
        Task {
            let translated = await AITranslator.translate(
                lyrics.map(\.text),
                into: translate.targetLanguage)
            var out: [Int: String] = [:]
            for (i, text) in translated.enumerated() where !text.isEmpty {
                if text != lyrics[safe: i]?.text { out[i] = text }
            }
            let result = out
            await MainActor.run {
                self.lines[videoId] = result
                self.inFlight.remove(key)
                self.working = false
            }
        }
    }
}

/// Latin transliteration. iOS does this natively, so there's no library and no
/// network — `StringTransform.toLatin` covers Cyrillic, Greek,
/// Japanese, Korean, Chinese, Arabic, Hebrew, Thai and Devanagari.
enum Romanize {
    static func toLatin(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let latin = text.applyingTransform(.toLatin, reverse: false)
        // Strip the accents the transform leaves behind, which is what makes it
        // readable rather than a pile of diacritics.
        return latin?.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    }

    /// Exactly the labels `Lyrics.detectScript` returns — anything else here
    /// would be a toggle that never matches a song. "Roman" is left out: it's
    /// already Latin.
    static let scripts: [(code: String, name: String)] = [
        ("Devanagari", "Hindi and Nepali"),
        ("Japanese", "Japanese"),
        ("Korean", "Korean"),
        ("Chinese", "Chinese"),
        ("Cyrillic", "Russian and Cyrillic"),
        ("Urdu", "Urdu and Arabic"),
        ("Bengali", "Bengali"),
        ("Gurmukhi", "Punjabi"),
        ("Gujarati", "Gujarati"),
        ("Tamil", "Tamil"),
        ("Telugu", "Telugu"),
        ("Kannada", "Kannada"),
        ("Malayalam", "Malayalam"),
        ("Odia", "Odia"),
    ]
}

/// Settings → Lyrics → Romanization.
final class RomanizePrefs: ObservableObject {
    static let shared = RomanizePrefs()

    @Published var enabled: Bool { didSet { save(enabled, "lyricsRomanizeEnabled") } }
    /// Show the romanisation in place of the original rather than under it.
    @Published var asMain: Bool { didSet { save(asMain, "lyricsRomanizeAsMain") } }
    @Published var scripts: [String] { didSet { save(scripts, "lyricsRomanizeList") } }

    private init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: "lyricsRomanizeEnabled") as? Bool ?? false
        asMain = d.object(forKey: "lyricsRomanizeAsMain") as? Bool ?? false
        scripts = d.stringArray(forKey: "lyricsRomanizeList")
            ?? Romanize.scripts.map(\.code)     // all on by default, as Android has them
    }

    func isOn(_ script: String) -> Bool { scripts.contains(script) }

    func set(_ script: String, on: Bool) {
        if on {
            if !scripts.contains(script) { scripts.append(script) }
        } else {
            scripts.removeAll { $0 == script }
        }
    }

    /// Whether these lyrics are in a script we've been asked to romanise.
    func applies(to lyrics: [LyricLine]) -> Bool {
        let sample = lyrics.prefix(12).map(\.text).joined(separator: " ")
        guard let script = Lyrics.detectScript(sample) else { return false }
        return isOn(script)
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
