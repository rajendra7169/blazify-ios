import Foundation

/// The player artwork layouts, matching Android Blaze's PlayerDesign.
enum PlayerDesign: String, CaseIterable, Identifiable {
    case classic, ring, fullArt, record, cassette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .ring: "Ring"
        case .fullArt: "Full Art"
        case .record: "Record"
        case .cassette: "Cassette"
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
