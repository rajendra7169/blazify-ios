import SwiftUI
import UIKit
import ImageIO

/// Decoded-image cache so home/library rails don't re-fetch — and flicker or
/// fail — every time a card scrolls out and back into a Lazy stack. (AsyncImage
/// caches nothing and cancels its load on reuse, which is why New-releases art
/// sometimes never appeared.)
enum ImageCache {
    static let store: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        // ~80 MB of decoded pixels; the OS evicts under pressure anyway.
        c.totalCostLimit = 80 * 1024 * 1024
        return c
    }()

    /// Disk-backed URL cache so art survives an app relaunch. Google serves
    /// these with long cache headers, so URLSession honours them for us.
    static func configureDiskCache() {
        let mb = ImageCacheSettings.limitMB
        URLCache.shared = URLCache(memoryCapacity: 16 * 1024 * 1024,
                                   diskCapacity: max(mb, 0) * 1024 * 1024)
    }
}

/// Google/YouTube image URLs carry their size in the path (`=w720-h720`).
/// Asking for the size we'll actually draw is the single biggest win for
/// loading speed — a 52pt row was pulling a 720×720 image.
enum ThumbSize {
    static func url(_ url: URL?, points: CGFloat?) -> URL? {
        guard let url else { return url }
        // Without a declared draw size we'd use whatever the catalogue put in
        // the URL — often 60px, which is why some art looked mushy. 544 is the
        // size YouTube Music itself serves for a row.
        // Cap at 1080: past that we're paying for pixels no phone shows.
        let pixels = points.map { min(Int(($0 * UIScreen.main.scale).rounded()), 1080) } ?? 544
        let s = url.absoluteString
        guard let range = s.range(of: "=w[0-9]+-h[0-9]+", options: .regularExpression) else {
            return url
        }
        return URL(string: s.replacingCharacters(in: range, with: "=w\(pixels)-h\(pixels)")) ?? url
    }
}

/// Drop-in replacement for AsyncImage that caches decoded images, survives
/// reuse, and fetches art at the size it's actually drawn.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    /// The side length this will be drawn at, in points. Supply it wherever the
    /// size is known — without it we fetch whatever size the URL already names.
    var size: CGFloat?
    /// Crop to fill, or letterbox the whole image in. Appearance → Fill the
    /// artwork frame flips this on the player.
    var fill = true
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    private var resolved: URL? { ThumbSize.url(url, points: size) }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                placeholder()
            }
        }
        .task(id: resolved) { await load() }
    }

    private func load() async {
        guard let target = resolved else { return }
        let key = target.absoluteString as NSString

        if let cached = ImageCache.store.object(forKey: key) {
            image = cached
            return
        }

        // Downloaded art is a local file:// URL.
        if target.isFileURL {
            guard let data = try? Data(contentsOf: target) else { return }
            guard let decoded = Self.downsample(data, to: size) ?? UIImage(data: data) else { return }
            store(decoded, key: key)
            return
        }

        guard let (data, _) = try? await URLSession.shared.data(from: target) else { return }
        guard let decoded = Self.downsample(data, to: size) ?? UIImage(data: data) else { return }
        store(decoded, key: key)
    }

    private func store(_ ui: UIImage, key: NSString) {
        let cost = Int(ui.size.width * ui.size.height * 4)
        ImageCache.store.setObject(ui, forKey: key, cost: cost)
        image = ui
    }

    /// Decode straight to the size we need. Full-size decoding is what makes a
    /// scrolling list of art stutter — the bytes are small, the bitmaps aren't.
    private static func downsample(_ data: Data, to points: CGFloat?) -> UIImage? {
        guard let points, points > 0,
              let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        let maxPixels = min(points * UIScreen.main.scale, 1080)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}
