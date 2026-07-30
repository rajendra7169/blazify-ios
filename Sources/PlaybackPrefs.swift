import Combine
import SwiftUI

/// Which audio stream to pick, mirroring Android's `AudioQuality`.
enum AudioQuality: String, CaseIterable, Identifiable {
    case auto, high, low
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "High"
        case .low: return "Low"
        }
    }
    var blurb: String {
        switch self {
        case .auto: return "Best available on Wi-Fi, lighter on cellular"
        case .high: return "Always the highest bitrate"
        case .low: return "Always the smallest stream"
        }
    }
}

/// Settings → Player and audio. Every option here does something — the ones
/// Android offers that iOS genuinely handles itself (audio offload, refresh
/// rate, task-clear) are left out rather than shown as dead switches.
final class PlaybackPrefs: ObservableObject {
    static let shared = PlaybackPrefs()

    // Audio
    @Published var quality: AudioQuality { didSet { save(quality.rawValue, "audioQuality") } }
    @Published var normalizeVolume: Bool { didSet { save(normalizeVolume, "audioNormalization"); audioChanged() } }
    @Published var loudnessTarget: Double { didSet { save(loudnessTarget, "loudnessLevel"); audioChanged() } }
    @Published var speed: Double { didSet { save(speed, "playbackSpeed"); audioChanged() } }
    @Published var preservePitch: Bool { didSet { save(preservePitch, "preservePitch"); audioChanged() } }
    @Published var gapless: Bool { didSet { save(gapless, "gaplessPlayback") } }
    @Published var crossfade: Bool { didSet { save(crossfade, "crossfadeEnabled") } }
    @Published var crossfadeDuration: Double { didSet { save(crossfadeDuration, "crossfadeDuration") } }

    // Queue
    @Published var persistentQueue: Bool { didSet { save(persistentQueue, "persistentQueue") } }
    @Published var autoplay: Bool { didSet { save(autoplay, "autoplay") } }
    @Published var autoRadioQueue: Bool { didSet { save(autoRadioQueue, "autoRadioQueue") } }
    @Published var autoLoadMore: Bool { didSet { save(autoLoadMore, "autoLoadMore") } }
    @Published var preventDuplicates: Bool { didSet { save(preventDuplicates, "preventDuplicateTracks") } }
    @Published var rememberShuffleRepeat: Bool { didSet { save(rememberShuffleRepeat, "rememberShuffleAndRepeat") } }
    @Published var shufflePlaylistFirst: Bool { didSet { save(shufflePlaylistFirst, "shufflePlaylistFirst") } }
    @Published var autoSkipOnError: Bool { didSet { save(autoSkipOnError, "autoSkipNextOnError") } }

    // Misc
    @Published var autoDownloadOnLike: Bool { didSet { save(autoDownloadOnLike, "autoDownloadOnLike") } }
    @Published var keepScreenOn: Bool { didSet { save(keepScreenOn, "keepScreenOn") } }
    @Published var resumeOnBluetooth: Bool { didSet { save(resumeOnBluetooth, "resumeOnBluetoothConnect") } }
    @Published var historyDays: Int { didSet { save(historyDays, "historyDuration") } }

    // Sleep timer defaults
    @Published var sleepFadeOut: Bool { didSet { save(sleepFadeOut, "sleepTimerFadeOut") } }
    @Published var sleepStopAfterSong: Bool { didSet { save(sleepStopAfterSong, "sleepTimerStopAfterCurrentSong") } }
    @Published var sleepDefaultMinutes: Double { didSet { save(sleepDefaultMinutes, "sleepTimerDefault") } }

    static let speedRange: ClosedRange<Double> = 0.5...2.0
    static let crossfadeRange: ClosedRange<Double> = 1...12
    /// 0 = keep forever, matching Android's "unlimited" history duration.
    static let historyOptions: [Int] = [0, 7, 30, 90, 365]

    private init() {
        let d = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }
        func number(_ key: String, _ fallback: Double) -> Double { d.object(forKey: key) as? Double ?? fallback }

        quality = AudioQuality(rawValue: d.string(forKey: "audioQuality") ?? "") ?? .auto
        normalizeVolume = flag("audioNormalization", true)
        loudnessTarget = number("loudnessLevel", -14)   // Android's default LUFS target
        speed = number("playbackSpeed", 1)
        preservePitch = flag("preservePitch", true)
        gapless = flag("gaplessPlayback", true)
        crossfade = flag("crossfadeEnabled", false)
        crossfadeDuration = number("crossfadeDuration", 4)

        persistentQueue = flag("persistentQueue", true)
        autoplay = flag("autoplay", true)
        autoRadioQueue = flag("autoRadioQueue", true)
        autoLoadMore = flag("autoLoadMore", true)
        preventDuplicates = flag("preventDuplicateTracks", false)
        rememberShuffleRepeat = flag("rememberShuffleAndRepeat", true)
        shufflePlaylistFirst = flag("shufflePlaylistFirst", false)
        autoSkipOnError = flag("autoSkipNextOnError", true)

        autoDownloadOnLike = flag("autoDownloadOnLike", false)
        keepScreenOn = flag("keepScreenOn", false)
        resumeOnBluetooth = flag("resumeOnBluetoothConnect", false)
        historyDays = d.object(forKey: "historyDuration") as? Int ?? 0

        sleepFadeOut = flag("sleepTimerFadeOut", true)
        sleepStopAfterSong = flag("sleepTimerStopAfterCurrentSong", false)
        sleepDefaultMinutes = number("sleepTimerDefault", 30)
    }

    /// The label for a history-retention choice.
    static func historyTitle(_ days: Int) -> String {
        switch days {
        case 0: return "Keep everything"
        case 7: return "1 week"
        case 30: return "1 month"
        case 90: return "3 months"
        default: return "1 year"
        }
    }

    /// Speed, pitch and normalisation have to reach the running player, not just
    /// the next song.
    private func audioChanged() {
        NotificationCenter.default.post(name: .blazifyAudioPrefsChanged, object: nil)
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

extension Notification.Name {
    static let blazifyAudioPrefsChanged = Notification.Name("blazifyAudioPrefsChanged")
}
