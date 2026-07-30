import AppIntents
import Foundation

extension BlazifyLink {
    /// The request a widget link stands for. Lives here rather than beside the
    /// URLs because `BlazifyRequest` is app-only — the widget target compiles
    /// the link definitions and must not need it.
    static func request(for url: URL) -> BlazifyRequest? {
        guard url.scheme == scheme else { return nil }
        switch url.host {
        case "resume": return .resume
        case "favourites": return .favourites
        case "downloads": return .downloads
        case "recognise": return .recognise
        default: return nil
        }
    }
}

/// What a Siri phrase or Shortcut asked us to do. The intents run outside the
/// app's view tree — the player is a `@StateObject` owned by `RootView`, so an
/// intent can't touch it directly. It leaves a request here and opens the app,
/// which performs it on the next foreground.
enum BlazifyRequest: Equatable {
    case resume, favourites, downloads, recognise
    /// A song Siri already resolved, by videoId.
    case play(String)

    private static let key = "pendingIntentRequest"
    private static let queryKey = "pendingIntentQuery"

    private var name: String {
        switch self {
        case .resume: return "resume"
        case .favourites: return "favourites"
        case .downloads: return "downloads"
        case .recognise: return "recognise"
        case .play: return "play"
        }
    }

    func store() {
        let d = UserDefaults.standard
        d.set(name, forKey: Self.key)
        if case .play(let videoId) = self {
            d.set(videoId, forKey: Self.queryKey)
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
        case "play":
            guard let query, !query.isEmpty else { return nil }
            return .play(query)
        default: return nil
        }
    }
}

/// A song Siri can resolve from what you said. A phrase slot has to be an
/// `AppEntity` or `AppEnum` — a plain String is rejected — so the spoken words
/// go through a query that searches the catalogue and hands Siri real songs to
/// choose between.
struct SongEntity: AppEntity, Identifiable {
    let id: String          // videoId
    let title: String
    let artist: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Song")
    static var defaultQuery = SongQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(artist)")
    }
}

struct SongQuery: EntityStringQuery {
    /// What Siri heard. Searching here means the match is resolved before the
    /// app even opens, so playback starts immediately rather than after a round
    /// trip.
    func entities(matching string: String) async throws -> [SongEntity] {
        let results = await YouTube.search(string)
        return results.prefix(8).map {
            SongEntity(id: $0.videoId, title: $0.title, artist: $0.artist)
        }
    }

    /// Re-resolving a song Shortcuts saved earlier. Answered from what's already
    /// on the device so a saved shortcut still works with no signal.
    func entities(for identifiers: [String]) async throws -> [SongEntity] {
        let known = Downloads.shared.tracks + PlayHistory.tracks
        return identifiers.compactMap { id in
            known.first { $0.videoId == id }
                .map { SongEntity(id: $0.videoId, title: $0.title, artist: $0.artist) }
        }
    }

    func suggestedEntities() async throws -> [SongEntity] {
        PlayHistory.recent.prefix(8).map {
            SongEntity(id: $0.videoId, title: $0.title, artist: $0.artist)
        }
    }
}

/// "Play <song> on Blazify".
struct PlaySongIntent: AppIntent {
    static var title: LocalizedStringResource = "Play a song"
    static var description = IntentDescription("Play a song in Blazify.")
    static var openAppWhenRun = true

    @Parameter(title: "Song", requestValueDialog: "What would you like to hear?")
    var song: SongEntity

    func perform() async throws -> some IntentResult {
        BlazifyRequest.play(song.id).store()
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
