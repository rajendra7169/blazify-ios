import Foundation

/// The player artwork layouts, matching Android Blaze's PlayerDesign.
enum PlayerDesign: String, CaseIterable, Identifiable {
    case classic, ring, fullArt, record, cassette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .ring: String(localized: "Ring")
        case .fullArt: String(localized: "Full Art")
        case .record: String(localized: "Record")
        case .cassette: String(localized: "Cassette")
        }
    }

    var subtitle: String {
        switch self {
        case .classic: "Square album art"
        case .ring: "Circular art with a progress ring"
        case .fullArt: "Art fills the whole screen"
        case .record: "Spinning vinyl record"
        case .cassette: "Retro cassette tape"
        }
    }
}
