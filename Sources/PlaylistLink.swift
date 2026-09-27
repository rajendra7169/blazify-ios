import Foundation

/// A playlist of your own, packed into a link.
///
/// The songs travel in the link itself, after the `#`, so the address never
/// reaches the site hosting the landing page — a fragment is not sent to a
/// server. Nothing is uploaded and nobody needs an account.
enum PlaylistLink {
    static let idLength = 11

    /// Songs past this are left out: the link, and the square that holds it, have their limits.
    static let maxSongs = 150

    private static let site = "https://rajendra7169.github.io/blazify/playlist"

    struct Shared: Equatable {
        let name: String
        let songIds: [String]
    }

    static func build(name: String, songIds: [String]) -> String {
        let ids = songIds.filter { $0.count == idLength }.prefix(maxSongs)
        let packedName = Data(name.utf8).base64URLEncoded
        return "\(site)#1.\(packedName).\(ids.joined())"
    }

    /// The playlist in this address, or nil when it is not one of our links.
    static func parse(_ url: URL) -> Shared? {
        let isPlaylistLink = url.host?.caseInsensitiveCompare("playlist") == .orderedSame
            || url.pathComponents.contains { $0.caseInsensitiveCompare("playlist") == .orderedSame }
        guard isPlaylistLink, let fragment = url.fragment else { return nil }

        let parts = fragment.components(separatedBy: ".")
        guard parts.count == 3, parts[0] == "1" else { return nil }
        guard let nameData = Data(base64URLEncoded: parts[1]),
              let name = String(data: nameData, encoding: .utf8),
              !name.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }

        var ids: [String] = []
        var rest = Substring(parts[2])
        while rest.count >= idLength {
            ids.append(String(rest.prefix(idLength)))
            rest = rest.dropFirst(idLength)
        }
        guard !ids.isEmpty else { return nil }
        return Shared(name: name, songIds: ids)
    }
}

private extension Data {
    /// URL-safe base64, no padding — it has to survive being in an address.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}
