import AppIntents
import Foundation

/// What a Siri phrase or Shortcut asked us to do. The intents run outside the
/// app's view tree — the player is a `@StateObject` owned by `RootView`, so an
/// intent can't touch it directly. It leaves a request here and opens the app,
/// which performs it on the next foreground.
enum BlazifyRequest: Equatable {
    case resume, favourites, downloads, recognise
    /// "Play <something> on Blazify" — the words Siri heard, to search for.
    case search(String)

    private static let key = "pendingIntentRequest"
    private static let queryKey = "pendingIntentQuery"

    private var name: String {
        switch self {
        case .resume: return "resume"
        case .favourites: return "favourites"
        case .downloads: return "downloads"
        case .recognise: return "recognise"
        case .search: return "search"
        }
    }

    func store() {
        let d = UserDefaults.standard
        d.set(name, forKey: Self.key)
        if case .search(let query) = self {
            d.set(query, forKey: Self.queryKey)
        } else {
            d.removeObject(forKey: Self.queryKey)
        }
    }

    /// Reads and clears in one go, so a request is never performed twice.
    static func take() -> BlazifyRequest? {
        let d = UserDefaults.standard
        guard let raw = d.string(forKey: key) else { return nil }
        let query = d.string(forKey: queryKey)
        d.removeObject(forKey: key)
        d.removeObject(forKey: queryKey)
        switch raw {
        case "resume": return .resume
        case "favourites": return .favourites
        case "downloads": return .downloads
        case "recognise": return .recognise
        case "search":
            guard let query, !query.isEmpty else { return nil }
            return .search(query)
        default: return nil
        }
    }
}

/// "Play <song> on Blazify". The parameter is what Siri transcribes, handed
/// straight to search — the first playable result wins, which is what you'd
/// expect from a spoken request.
struct PlaySongIntent: AppIntent {
    static var title: LocalizedStringResource = "Play a song"
    static var description = IntentDescription("Search Blazify and play the best match.")
    static var openAppWhenRun = true

    @Parameter(title: "Song", requestValueDialog: "What would you like to hear?")
    var song: String

    func perform() async throws -> some IntentResult {
        BlazifyRequest.search(song).store()
        return .result()
    }
}

struct ResumeBlazifyIntent: AppIntent {
    static var title: LocalizedStringResource = "Play"
    static var description = IntentDescription("Carry on where Blazify left off.")
    /// Playback needs the app's audio session, so bring it forward.
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        BlazifyRequest.resume.store()
        return .result()
    }
}

struct PlayFavouritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Play favourites"
    static var description = IntentDescription("Shuffle the songs you've hearted.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        BlazifyRequest.favourites.store()
        return .result()
    }
}

struct PlayDownloadsIntent: AppIntent {
    static var title: LocalizedStringResource = "Play downloads"
    static var description = IntentDescription("Shuffle everything saved on this device — works with no signal.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        BlazifyRequest.downloads.store()
        return .result()
    }
}

struct RecogniseSongIntent: AppIntent {
    static var title: LocalizedStringResource = "Identify the song"
    static var description = IntentDescription("Listen and name the song playing nearby.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        BlazifyRequest.recognise.store()
        return .result()
    }
}

/// The phrases Siri will accept. Every phrase has to contain
/// `\(.applicationName)` — that's the token Siri matches, and it's why "Play
/// Blazify" resolves at all. Without a registered intent, Siri reads "play X"
/// as a request for media called X and finds nothing, which is the
/// "could not find app" you were getting.
struct BlazifyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumeBlazifyIntent(),
            phrases: [
                "Play \(.applicationName)",
                "Resume \(.applicationName)",
                "Start \(.applicationName)",
                "Play music on \(.applicationName)",
            ],
            shortTitle: "Play",
            systemImageName: "play.fill")

        AppShortcut(
            intent: PlaySongIntent(),
            phrases: [
                "Play \(\.$song) on \(.applicationName)",
                "Play \(\.$song) with \(.applicationName)",
                "Listen to \(\.$song) on \(.applicationName)",
            ],
            shortTitle: "Play a song",
            systemImageName: "music.note")

        AppShortcut(
            intent: PlayFavouritesIntent(),
            phrases: [
                "Play my favourites on \(.applicationName)",
                "Play liked songs on \(.applicationName)",
            ],
            shortTitle: "Favourites",
            systemImageName: "heart.fill")

        AppShortcut(
            intent: PlayDownloadsIntent(),
            phrases: [
                "Play my downloads on \(.applicationName)",
                "Play offline music on \(.applicationName)",
            ],
            shortTitle: "Downloads",
            systemImageName: "arrow.down.circle.fill")

        AppShortcut(
            intent: RecogniseSongIntent(),
            phrases: [
                "Identify this song with \(.applicationName)",
                "What's playing on \(.applicationName)",
            ],
            shortTitle: "Identify",
            systemImageName: "waveform")
    }
}
