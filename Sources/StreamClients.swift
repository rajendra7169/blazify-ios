import Combine
import SwiftUI

/// The InnerTube clients that can resolve an audio stream, ported from Android's
/// Stream sources screen. Only these three answer for music with a direct,
/// un-ciphered URL — TVHTML5 errors, WEB_REMIX comes back unplayable, and both
/// creator clients demand a login, so they aren't offered.
enum StreamClient: String, CaseIterable, Identifiable, Codable {
    case androidVR = "ANDROID_VR"
    case visionOS = "VISIONOS"
    case ios = "IOS"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .androidVR: return "Android VR"
        case .visionOS: return "visionOS"
        case .ios: return "iOS"
        }
    }

    var blurb: String {
        switch self {
        case .androidVR: return "Needs no token, and the only one that reports track loudness"
        case .visionOS: return "Uncapped streams, no loudness data"
        case .ios: return "Fallback when the other two are refused"
        }
    }

    /// `X-Youtube-Client-Name`.
    var number: String {
        switch self {
        case .androidVR: return "28"
        case .visionOS: return "101"
        case .ios: return "5"
        }
    }

    var version: String {
        switch self {
        case .androidVR: return "1.62.27"
        case .visionOS: return "0.1"
        case .ios: return "20.10.4"
        }
    }

    var userAgent: String {
        switch self {
        case .androidVR: return "com.google.android.apps.youtube.vr.oculus/1.62.27 (Linux; U; Android 12; GB) gzip"
        case .visionOS, .ios: return YouTube.visionUA
        }
    }

    /// The `context.client` block this client expects.
    var context: [String: Any] {
        switch self {
        case .androidVR:
            return ["clientName": rawValue, "clientVersion": version,
                    "deviceMake": "Oculus", "deviceModel": "Quest 3",
                    "osName": "Android", "osVersion": "12", "androidSdkVersion": 32,
                    "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        case .visionOS:
            return ["clientName": rawValue, "clientVersion": version,
                    "deviceMake": "Apple", "deviceModel": "RealityDevice14,1",
                    "osName": "visionOS", "osVersion": "1.3.21O771",
                    "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        case .ios:
            return ["clientName": rawValue, "clientVersion": version,
                    "deviceMake": "Apple", "deviceModel": "iPhone16,2",
                    "osName": "iOS", "osVersion": "18.3.2.22D82",
                    "hl": ContentPrefs.locale.hl, "gl": ContentPrefs.locale.gl]
        }
    }
}

/// The order stream clients are tried in. Android VR leads because it's the one
/// that needs no proof-of-origin token and the only one that hands back the
/// loudness the volume normalisation uses; the others are the fallback chain if
/// YouTube ever refuses it.
final class StreamPrefs: ObservableObject {
    static let shared = StreamPrefs()

    @Published var order: [StreamClient] {
        didSet {
            UserDefaults.standard.set(order.map(\.rawValue), forKey: "streamSourceOrder")
        }
    }

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: "streamSourceOrder") ?? []
        let known = StreamClient.allCases
        let restored = stored.compactMap(StreamClient.init(rawValue:))
        // Append anything the stored order predates, so a new client is used
        // rather than silently dropped.
        order = restored + known.filter { !restored.contains($0) }
    }
}
