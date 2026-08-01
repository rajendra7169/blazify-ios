import Combine
import CryptoKit
import Foundation

/// Last.fm scrobbling. The credentials are yours: no API key is baked into
/// this repo, so
/// rather than ship an empty integration the key and secret are entered in
/// Settings and kept in the Keychain, next to the YouTube cookie.
/// The rules: at least 30 s long, scrobbled at half the track or four
/// minutes in, whichever comes first. Kept outside the main-actor class so the
/// player's time observer can read them without hopping actors.
enum LastFMRules {
    static let minDuration: Double = 30
    static let scrobbleFraction: Double = 0.5
    static let scrobbleCap: Double = 240
}

final class LastFM: ObservableObject {
    static let shared = LastFM()

    @Published private(set) var username: String?
    @Published var scrobbling: Bool { didSet { UserDefaults.standard.set(scrobbling, forKey: "lastfmScrobbling") } }
    @Published var loveOnFavorite: Bool { didSet { UserDefaults.standard.set(loveOnFavorite, forKey: "lastfmLoveOnFavorite") } }
    @Published var status: String?

    private var apiKey: String? { Keychain.get("lastfmApiKey") }
    private var secret: String? { Keychain.get("lastfmSecret") }
    private var session: String? { Keychain.get("lastfmSession") }

    var hasCredentials: Bool { !(apiKey ?? "").isEmpty && !(secret ?? "").isEmpty }
    var isConnected: Bool { session != nil && username != nil }

    private init() {
        scrobbling = UserDefaults.standard.object(forKey: "lastfmScrobbling") as? Bool ?? true
        loveOnFavorite = UserDefaults.standard.object(forKey: "lastfmLoveOnFavorite") as? Bool ?? false
        username = UserDefaults.standard.string(forKey: "lastfmUsername")
    }

    func saveCredentials(key: String, secret: String) {
        Keychain.set(key.trimmingCharacters(in: .whitespaces), for: "lastfmApiKey")
        Keychain.set(secret.trimmingCharacters(in: .whitespaces), for: "lastfmSecret")
        objectWillChange.send()
    }

    func disconnect() {
        Keychain.set(nil, for: "lastfmSession")
        UserDefaults.standard.removeObject(forKey: "lastfmUsername")
        username = nil
        status = nil
    }

    // MARK: Auth — token, then the browser, then a session

    /// Step one: a request token, and the page to approve it on.
    func requestToken() async -> URL? {
        guard let apiKey else { return nil }
        guard let json = await call(["method": "auth.getToken"], signed: true),
              let token = json["token"] as? String else {
            await MainActor.run { self.status = "Couldn't get a token — check the key and secret." }
            return nil
        }
        pendingToken = token
        return URL(string: "https://www.last.fm/api/auth/?api_key=\(apiKey)&token=\(token)")
    }

    private var pendingToken: String?

    /// Step two, after approving in the browser.
    func completeAuth() async {
        guard let token = pendingToken else {
            await MainActor.run { self.status = "Start the connection first." }
            return
        }
        guard let json = await call(["method": "auth.getSession", "token": token], signed: true),
              let session = json["session"] as? [String: Any],
              let key = session["key"] as? String,
              let name = session["name"] as? String else {
            await MainActor.run { self.status = "Not approved yet — approve in the browser, then tap again." }
            return
        }
        Keychain.set(key, for: "lastfmSession")
        UserDefaults.standard.set(name, forKey: "lastfmUsername")
        pendingToken = nil
        await MainActor.run {
            self.username = name
            self.status = "Connected as \(name)."
        }
    }

    // MARK: Scrobbling

    func nowPlaying(_ track: Track) async {
        guard scrobbling, let session else { return }
        _ = await call(["method": "track.updateNowPlaying",
                        "artist": track.artist, "track": track.title,
                        "sk": session], signed: true, post: true)
    }

    func scrobble(_ track: Track, startedAt: Date) async {
        guard scrobbling, let session else { return }
        _ = await call(["method": "track.scrobble",
                        "artist": track.artist, "track": track.title,
                        "timestamp": String(Int(startedAt.timeIntervalSince1970)),
                        "sk": session], signed: true, post: true)
    }

    func love(_ track: Track, loved: Bool) async {
        guard loveOnFavorite, let session else { return }
        _ = await call(["method": loved ? "track.love" : "track.unlove",
                        "artist": track.artist, "track": track.title,
                        "sk": session], signed: true, post: true)
    }

    // MARK: Transport

    /// `api_sig` is an md5 of every parameter sorted by name, concatenated
    /// key-then-value, with the shared secret on the end — exactly what
 /// `Map.apiSig` does.
    private func signature(_ params: [String: String]) -> String {
        guard let secret else { return "" }
        let joined = params.sorted { $0.key < $1.key }
            .map { $0.key + $0.value }.joined() + secret
        return Insecure.MD5.hash(data: Data(joined.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func call(_ params: [String: String], signed: Bool,
                      post: Bool = false) async -> [String: Any]? {
        guard let apiKey else { return nil }
        var all = params
        all["api_key"] = apiKey
        if signed { all["api_sig"] = signature(all) }
        all["format"] = "json"

        var comps = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
        let items = all.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req: URLRequest
        if post {
            req = URLRequest(url: comps.url!)
            req.httpMethod = "POST"
            var body = URLComponents()
            body.queryItems = items
            req.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        } else {
            comps.queryItems = items
            guard let url = comps.url else { return nil }
            req = URLRequest(url: url)
        }
        req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }
}
