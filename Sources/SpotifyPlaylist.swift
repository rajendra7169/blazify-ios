import Foundation

/// Reads a Spotify playlist or album from its link.
///
/// Spotify's own API needs an app registration, and the token its web player
/// hands out anonymously is now refused for anything but the player itself. The
/// page behind a share link, though, carries the whole track list in a script
/// tag: what the player would draw, ready to read, with no key and no sign-in.
///
/// That page stops at 100 tracks, which is the one thing this cannot do
/// anything about — ``Playlist/mayHaveMore`` says when a list was long enough to
/// be cut, so the person importing is told rather than left wondering.
enum SpotifyPlaylist {
    /// A track as Spotify describes it; the names are what the search will look for.
    struct Track: Equatable {
        let title: String
        let artists: String
        let durationSeconds: Int
    }

    struct Playlist: Equatable {
        let name: String
        let tracks: [Track]
        let mayHaveMore: Bool
    }

    /// The most a share page will list, whatever the playlist really holds.
    private static let pageLimit = 100

    enum Failure: LocalizedError {
        case notASpotifyLink
        case noTrackList

        var errorDescription: String? {
            switch self {
            case .notASpotifyLink: String(localized: "That is not a Spotify playlist link.")
            case .noTrackList: String(localized: "Could not read that playlist.")
            }
        }
    }

    /// What the link points at, or nil when it is not a Spotify playlist or
    /// album — a track link, a profile, or something that is not Spotify at all.
    static func parseLink(_ link: String) -> (kind: String, id: String)? {
        let pattern = "(?:open\\.spotify\\.com/(?:intl-[a-z-]+/)?|spotify:)(playlist|album)[:/]([A-Za-z0-9]+)"
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let kind = Range(match.range(at: 1), in: text),
              let id = Range(match.range(at: 2), in: text)
        else { return nil }
        return (String(text[kind]), String(text[id]))
    }

    static func read(_ link: String) async throws -> Playlist {
        guard let (kind, id) = parseLink(link) else { throw Failure.notASpotifyLink }
        guard let url = URL(string: "https://open.spotify.com/embed/\(kind)/\(id)") else {
            throw Failure.notASpotifyLink
        }
        var request = URLRequest(url: url)
        // Served to a browser; without this the page comes back without the
        // script tag everything here depends on.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let page = String(data: data, encoding: .utf8) else { throw Failure.noTrackList }
        return try parse(page)
    }

    /// Pulled out of ``read(_:)`` so it can be checked without the network.
    static func parse(_ page: String) throws -> Playlist {
        guard let json = nextData(in: page),
              let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let data = state["data"] as? [String: Any],
              let entity = data["entity"] as? [String: Any],
              let list = entity["trackList"] as? [[String: Any]]
        else { throw Failure.noTrackList }

        let tracks: [Track] = list.compactMap { row in
            let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !title.isEmpty else { return nil }
            let ms = (row["duration"] as? NSNumber)?.doubleValue ?? 0
            return Track(
                title: title,
                artists: (row["subtitle"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "",
                durationSeconds: Int(ms / 1000))
        }
        guard !tracks.isEmpty else { throw Failure.noTrackList }

        let name = (entity["name"] as? String)?.trimmingCharacters(in: .whitespaces)
        return Playlist(
            name: name?.isEmpty == false ? name! : String(localized: "Spotify playlist"),
            tracks: tracks,
            mayHaveMore: list.count >= pageLimit)
    }

    /// The JSON inside the page's `__NEXT_DATA__` script tag.
    ///
    /// Found by walking to the tag's end rather than with a regular expression:
    /// the body is a whole playlist, and a lazy `.*?` across a hundred kilobytes
    /// of it is slow enough to feel on a phone.
    private static func nextData(in page: String) -> String? {
        guard let open = page.range(of: "<script id=\"__NEXT_DATA__\"", options: .literal),
              let bodyStart = page.range(of: ">", range: open.upperBound..<page.endIndex),
              let close = page.range(of: "</script>", range: bodyStart.upperBound..<page.endIndex)
        else { return nil }
        return String(page[bodyStart.upperBound..<close.lowerBound])
    }
}
