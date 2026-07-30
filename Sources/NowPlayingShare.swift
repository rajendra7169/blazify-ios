import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// What the widget needs to draw the turntable, and the one channel the app has
/// for handing it over. Compiled into BOTH targets — the app writes, the widget
/// reads, and neither can drift from the other's idea of the shape.
///
/// A widget extension is a separate process with its own sandbox, so the only
/// way to pass it data is a container both sides are entitled to. That's the App
/// Group. If the signing profile doesn't carry the entitlement, `defaults` falls
/// back to the target's own standard store, the widget reads nothing, and it
/// draws its idle face instead of crashing or showing a stale song.
struct SharedTrack: Codable, Equatable {
    var title: String
    var artist: String
    var videoId: String
    var isPlaying: Bool
    var duration: Double
    /// Position at the moment of writing, plus when that was. The widget can't
    /// be woken four times a second, so it interpolates from these two rather
    /// than showing a timestamp that's a minute stale.
    var position: Double
    var stamp: Date

    /// Where the playhead is now, assuming playback continued as it was.
    func position(at date: Date) -> Double {
        guard isPlaying else { return min(position, duration) }
        return min(position + date.timeIntervalSince(stamp), duration)
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

enum NowPlayingShare {
    /// Must match the entitlement on both targets.
    static let appGroup = "group.com.rajendra.blazifyplayer"

    private static let key = "widget.nowPlaying"

    /// The group store when we're entitled to it, the local one when we're not.
    /// Writing to the local store is harmless — nothing reads it — so the app
    /// never has to branch on whether the entitlement made it through signing.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Artwork goes in the group container as a file rather than into defaults:
    /// a widget's payload budget is small, and a base64 JPEG in a plist would
    /// eat it for no reason.
    static var artFile: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-art.jpg")
    }

    static func read() -> SharedTrack? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SharedTrack.self, from: data)
    }

    static func write(_ track: SharedTrack?) {
        guard let track else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(track) {
            defaults.set(data, forKey: key)
        }
    }

    #if canImport(UIKit)
    /// Read the artwork the app last handed over. Returns nil with no App Group,
    /// which is exactly the placeholder case the widget already draws.
    static func artwork() -> UIImage? {
        guard let url = artFile, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Squared, downscaled and re-encoded. The label on the record is ~110pt
    /// across at its largest, so anything past 320px is bytes the widget pays
    /// for on every reload and never shows.
    static func writeArtwork(_ image: UIImage?) {
        guard let url = artFile else { return }
        guard let image else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let side: CGFloat = 320
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let scaled = UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                             format: format).image { _ in
            // Aspect-fill, so a non-square thumbnail crops rather than letterboxes
            // — a letterboxed label looks like a bug on a round record.
            let ratio = max(side / max(image.size.width, 1), side / max(image.size.height, 1))
            let box = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.draw(in: CGRect(x: (side - box.width) / 2, y: (side - box.height) / 2,
                                  width: box.width, height: box.height))
        }
        try? scaled.jpegData(compressionQuality: 0.8)?.write(to: url, options: .atomic)
    }
    #endif
}
