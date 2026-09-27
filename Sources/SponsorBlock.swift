import CryptoKit
import Foundation

/// The parts of a video that are not the song, as marked by SponsorBlock's community.
///
/// Asked for by the first four characters of the video id's hash rather than the
/// id itself: the answer covers every video whose hash starts the same way, so
/// the server is never told which song is playing. That costs a slightly bigger
/// reply and keeps the promise this app makes about not being watched.
enum SponsorBlock {
    /// What can be skipped. Only the ones that make sense for music are offered.
    enum Category: String, CaseIterable, Identifiable {
        /// Talking, credits, silence — everything in a music video that is not the song.
        case nonMusic = "music_offtopic"
        case sponsor
        case selfPromotion = "selfpromo"
        case intro
        case outro

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nonMusic: String(localized: "Anything that is not music")
            case .sponsor: String(localized: "Sponsor breaks")
            case .selfPromotion: String(localized: "Self-promotion")
            case .intro: String(localized: "Intros")
            case .outro: String(localized: "Outros and credits")
            }
        }
    }

    /// A stretch to skip, in seconds on the player's own clock.
    struct Segment: Equatable {
        let start: Double
        let end: Double
        let category: Category
    }

    private static let api = "https://sponsor.ajay.app/api/skipSegments"

    static func segments(videoId: String, categories: Set<Category>) async -> [Segment] {
        guard !categories.isEmpty, !videoId.isEmpty else { return [] }
        let wanted = categories.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        var components = URLComponents(string: "\(api)/\(hashPrefix(videoId))")
        components?.queryItems = [URLQueryItem(name: "categories", value: "[\(wanted)]")]
        guard let url = components?.url else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return parse(data, videoId: videoId, categories: categories)
        } catch {
            return []
        }
    }

    /// The first four characters of the video id's SHA-256, which is all the server is told.
    static func hashPrefix(_ videoId: String) -> String {
        SHA256.hash(data: Data(videoId.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(4)
            .lowercased()
    }

    /// The segments for one video, out of an answer that covers many.
    ///
    /// Only what the community agrees on is kept: a segment voted below zero is
    /// one people say is wrong, and skipping on a wrong mark is worse than not
    /// skipping at all.
    static func parse(_ data: Data, videoId: String, categories: Set<Category>) -> [Segment] {
        guard let videos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        let mine = videos.first { $0["videoID"] as? String == videoId }
        guard let rows = mine?["segments"] as? [[String: Any]] else { return [] }

        return rows.compactMap { row -> Segment? in
            guard (row["actionType"] as? String ?? "skip") == "skip",
                  ((row["votes"] as? NSNumber)?.intValue ?? 0) >= 0,
                  let name = row["category"] as? String,
                  let category = Category(rawValue: name), categories.contains(category),
                  let pair = row["segment"] as? [NSNumber], pair.count >= 2
            else { return nil }
            let start = pair[0].doubleValue, end = pair[1].doubleValue
            guard end > start else { return nil }
            return Segment(start: start, end: end, category: category)
        }
        .sorted { $0.start < $1.start }
    }

    /// The segment the player is inside now, or nil.
    ///
    /// The last half second is left alone: jumping out of a segment that is
    /// about to end anyway only makes the music stutter.
    static func segment(in segments: [Segment], at position: Double) -> Segment? {
        segments.first { position >= $0.start && position < $0.end - 0.5 }
    }
}
