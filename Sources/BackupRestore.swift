import SwiftUI
import UniformTypeIdentifiers

/// Settings → Backup and restore. Playlists
/// live on YouTube and come back with the account, so what's actually at risk is
/// what only exists on this phone: favourites, listening history, search history
/// and every setting. All of it goes into one JSON file you keep yourself.
enum BlazifyBackup {
    /// Defaults worth carrying to a new install. Deliberately excludes session
    /// state — the saved queue, cached stream URLs and the login cookie stay
    /// behind, since restoring those onto another device is meaningless.
    static let settingKeys: [String] = [
        // Look & feel
        "themeMode", "selectedThemeColor", "dynamicTheme", "pureBlack",
        "playerDesign", "playerBackground", "sliderStyle", "squigglySlider",
        "miniPlayerDesign", "miniPlayerBackground", "navBarStyle", "slimNavBar",
        "defaultOpenTab", "gridItemSize", "showHomeGreeting", "showHomeSearchBar",
        // Lyrics
        "blazifyLyricsStyle", "lyricsGlowEffect", "lyricsAnimationStyle",
        "lyricsTextSize", "lyricsLineSpacing", "lyricsPosition",
        "respectAgentPositioning", "lyricsClick", "lyricsScrollKey",
        "hideStatusBarOnFullscreen", "lyricsProviderOrder",
        // Playback
        "audioQuality", "audioNormalization", "loudnessLevel", "playbackSpeed",
        "preservePitch", "crossfadeEnabled", "crossfadeDuration",
        "persistentQueue", "autoplay", "autoRadioQueue", "autoLoadMore",
        "preventDuplicateTracks", "rememberShuffleAndRepeat", "shufflePlaylistFirst",
        "autoSkipNextOnError", "autoDownloadOnLike", "keepScreenOn",
        "resumeOnBluetoothConnect", "historyDuration", "sleepTimerFadeOut",
        "sleepTimerStopAfterCurrentSong", "sleepTimerDefault", "streamSourceOrder",
        // Content + privacy
        "contentLanguage", "contentCountry", "hideExplicit", "hideVideoSongs",
        "showArtistDescription", "showArtistMonthlyListeners",
        "showArtistSubscriberCount", "randomizeHomeOrder", "showMostStatsPlaylists",
        "pauseListenHistory", "pauseSearchHistory",
        // Storage
        "enableSongCache", "maxSongCacheMB", "maxImageCacheMB",
    ]

    /// Raw data blobs (JSON already) that ride along verbatim.
    static let dataKeys: [String] = ["favoriteTracks", "playEvents", "playedTracks"]
    static let listKeys: [String] = ["searchHistory"]

    static func make() -> Data? {
        let d = UserDefaults.standard
        var settings: [String: String] = [:]
        for key in settingKeys {
            guard let value = d.object(forKey: key) else { continue }
            // Everything is stringified so one flat dictionary can hold bools,
            // numbers, strings and arrays without a type tag per entry.
            if let array = value as? [String] {
                settings[key] = "[]" + array.joined(separator: "\u{1}")
            } else {
                settings[key] = String(describing: value)
            }
        }
        var blobs: [String: String] = [:]
        for key in dataKeys {
            if let data = d.data(forKey: key) {
                blobs[key] = data.base64EncodedString()
            }
        }
        var lists: [String: [String]] = [:]
        for key in listKeys {
            if let list = d.stringArray(forKey: key) { lists[key] = list }
        }

        let bundle: [String: Any] = [
            "app": "Blazify", "version": 1,
            "settings": settings, "blobs": blobs, "lists": lists,
        ]
        return try? JSONSerialization.data(withJSONObject: bundle, options: .prettyPrinted)
    }

    /// Returns what was restored, or nil if the file isn't one of ours.
    @discardableResult
    static func restore(from data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["app"] as? String == "Blazify" else { return nil }
        let d = UserDefaults.standard
        var restored = 0

        if let settings = json["settings"] as? [String: String] {
            for (key, raw) in settings where settingKeys.contains(key) {
                if raw.hasPrefix("[]") {
                    let body = String(raw.dropFirst(2))
                    d.set(body.isEmpty ? [] : body.components(separatedBy: "\u{1}"), forKey: key)
                } else if raw == "true" || raw == "false" {
                    d.set(raw == "true", forKey: key)
                } else if let number = Double(raw) {
                    // Whole numbers go back as Int so `integer(forKey:)` reads them.
                    if number == number.rounded(), abs(number) < 1e9 {
                        d.set(Int(number), forKey: key)
                    } else {
                        d.set(number, forKey: key)
                    }
                } else {
                    d.set(raw, forKey: key)
                }
                restored += 1
            }
        }
        if let blobs = json["blobs"] as? [String: String] {
            for (key, encoded) in blobs where dataKeys.contains(key) {
                if let blob = Data(base64Encoded: encoded) {
                    d.set(blob, forKey: key)
                    restored += 1
                }
            }
        }
        if let lists = json["lists"] as? [String: [String]] {
            for (key, list) in lists where listKeys.contains(key) {
                d.set(list, forKey: key)
                restored += 1
            }
        }
        return restored
    }
}

/// The exported file itself.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
