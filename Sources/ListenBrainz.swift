import Combine
import Foundation

/// Sends what is playing to ListenBrainz.
///
/// The open counterpart to Last.fm: the history belongs to the listener, who can
/// take it away again. One address, one token the listener pastes in, and two
/// kinds of message — "this is on now", and "this one counted".
///
/// The token is full access to somebody's listening history, so it lives in the
/// Keychain next to the Last.fm session and the YouTube cookie, never in a file.
final class ListenBrainz: ObservableObject {
    static let shared = ListenBrainz()

    private static let api = "https://api.listenbrainz.org/1"

    /// Named in every submission, so a listener can see where a play came from.
    private static let client = "Blazify"

    @Published private(set) var username: String?
    @Published var scrobbling: Bool {
        didSet { UserDefaults.standard.set(scrobbling, forKey: "listenBrainzEnabled") }
    }
    /// What the last check said, shown under the field.
    @Published var status: String?
    @Published private(set) var checking = false

    private var token: String? { Keychain.get("listenBrainzToken") }

    var isConnected: Bool { !(token ?? "").isEmpty && username != nil }

    private init() {
        scrobbling = UserDefaults.standard.object(forKey: "listenBrainzEnabled") as? Bool ?? false
        username = UserDefaults.standard.string(forKey: "listenBrainzUsername")
    }

    /// Checks a token before anything is sent with it: a token that does not work
    /// would otherwise fail silently, for weeks, on every song.
    @MainActor
    func connect(token typed: String) async {
        let candidate = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !checking else { return }
        checking = true
        status = String(localized: "Checking the token…")
        let name = await Self.userName(of: candidate)
        checking = false
        guard let name else {
            status = String(localized: "ListenBrainz did not accept that token.")
            return
        }
        Keychain.set(candidate, for: "listenBrainzToken")
        UserDefaults.standard.set(name, forKey: "listenBrainzUsername")
        username = name
        scrobbling = true
        status = String(localized: "Sending as \(name).")
    }

    @MainActor
    func forget() {
        Keychain.set(nil, for: "listenBrainzToken")
        UserDefaults.standard.removeObject(forKey: "listenBrainzUsername")
        username = nil
        scrobbling = false
        status = nil
    }

    /// The name behind a token, or nil when ListenBrainz will not have it.
    static func userName(of token: String) async -> String? {
        guard let url = URL(string: "\(api)/validate-token") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Token \(token.trimmingCharacters(in: .whitespaces))",
                         forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["valid"] as? Bool == true
        else { return nil }
        return json["user_name"] as? String
    }

    // MARK: Submitting

    func nowPlaying(_ track: Track) async {
        await send(payload(listenType: "playing_now", track: track, listenedAt: nil))
    }

    func scrobble(_ track: Track, startedAt: Date) async {
        await send(payload(listenType: "single", track: track,
                           listenedAt: Int(startedAt.timeIntervalSince1970)))
    }

    private func send(_ body: [String: Any]?) async {
        guard scrobbling, let body, let key = token?.trimmingCharacters(in: .whitespaces),
              !key.isEmpty, let url = URL(string: "\(Self.api)/submit-listens"),
              let data = try? JSONSerialization.data(withJSONObject: body)
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        // A listen that does not arrive is not worth interrupting the music for.
        _ = try? await URLSession.shared.data(for: request)
    }

    /// One submission, in the shape ListenBrainz asks for.
    ///
    /// A play with no artist or title is not sent at all: it would arrive as an
    /// entry nobody could read, in a history the listener keeps for years.
    func payload(listenType: String, track: Track, listenedAt: Int?) -> [String: Any]? {
        let artist = track.artist.trimmingCharacters(in: .whitespaces)
        let title = track.title.trimmingCharacters(in: .whitespaces)
        guard !artist.isEmpty, !title.isEmpty else { return nil }

        var info: [String: Any] = [
            "media_player": Self.client,
            "submission_client": Self.client,
        ]
        if track.duration > 0 { info["duration"] = Int(track.duration) }
        if !track.videoId.isEmpty, !LocalMusic.isLocal(track.videoId) {
            info["music_service"] = "music.youtube.com"
            info["origin_url"] = "https://music.youtube.com/watch?v=\(track.videoId)"
        }

        var listen: [String: Any] = [
            "track_metadata": [
                "artist_name": artist,
                "track_name": title,
                "additional_info": info,
            ],
        ]
        if let listenedAt { listen["listened_at"] = listenedAt }
        return ["listen_type": listenType, "payload": [listen]]
    }
}
