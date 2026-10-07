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

    /// Fetches and decodes an image ahead of the view that will ask for it,
    /// under the key that view will use — the URL at the size it names, with
    /// no draw size given. For the player's cover of the song after this one.
    static func prefetch(_ url: URL?) async {
        guard let target = ThumbSize.url(url, points: nil), !target.isFileURL else { return }
        let key = "\(target.absoluteString)|0" as NSString
        guard store.object(forKey: key) == nil else { return }
        guard let data = await ArtFetch.data(from: target), let decoded = UIImage(data: data) else { return }
        store.setObject(decoded, forKey: key, cost: Int(decoded.size.width * decoded.size.height * 4))
    }

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
enum ArtFetch {
    /// Artwork bytes, dropping back from a maxres still to the size every video
    /// is guaranteed to have.
    static func data(from url: URL) async -> Data? {
        if let data = try? await URLSession.shared.data(from: url).0, !data.isEmpty {
            return data
        }
        guard url.absoluteString.contains("maxresdefault"),
              let fallback = URL(string: url.absoluteString
                  .replacingOccurrences(of: "maxresdefault", with: "hqdefault"))
        else { return nil }
        return try? await URLSession.shared.data(from: fallback).0
    }
}

enum ThumbSize {
    static func url(_ url: URL?, points: CGFloat?) -> URL? {
        guard let url else { return url }
        // Cap at 1080: past that we're paying for pixels no phone shows.
        let s = url.absoluteString
        guard let range = s.range(of: "=w[0-9]+-h[0-9]+", options: .regularExpression) else {
            return url
        }
        let pixels: Int
        if let points {
            pixels = min(Int((points * UIScreen.main.scale).rounded()), 1080)
        } else {
            // No declared draw size. The catalogue's own number is often 60px,
            // so raise it to the 544 YouTube Music serves for a row — but never
            // LOWER it: the full player asks for 1080 in the URL precisely
            // because it draws edge to edge, and knocking that back to 544 made
            // its artwork soft. Take whichever is larger.
            let existing = Int(s[range].dropFirst(2).prefix { $0.isNumber }) ?? 0
            pixels = min(max(existing, 544), 1080)
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
    /// Fade from one picture to the next instead of cutting. For the player's
    /// cover, which changes on every skip in front of whoever pressed it; a
    /// row in a list that scrolls is better off with the cut.
    var crossfade = false
    /// The Blazify logo in black and white over the placeholder, while the
    /// picture loads and where there is none. Off for faces — a profile picture
    /// with a logo on it reads as the wrong person.
    var logo = true
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    private var resolved: URL? { ThumbSize.url(url, points: size) }

    /// The pixel size we'll decode to. `nil` size means "whatever the file is".
    private var decodePixels: Int {
        guard let size, size > 0 else { return 0 }
        return Int(min(size * UIScreen.main.scale, 1080))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
            } else {
                placeholder()
                    // ArtPlaceholder carries the mark already; two would sit on top of each other.
                    .overlay { if logo, Placeholder.self != ArtPlaceholder.self { ArtLogoMark() } }
            }
        }
        .animation(crossfade ? Animation.easeInOut(duration: 0.3) : nil, value: image.map { ObjectIdentifier($0) })
        .task(id: "\(resolved?.absoluteString ?? "")|\(decodePixels)") { await load() }
    }

    private func load() async {
        guard let target = resolved else { return }
        // The size has to be part of the key. A remote URL carries its size in
        // the string, so each size caches separately — but a LOCAL file's URL is
        // identical whatever size we want it at. That let the first 48pt row to
        // decode a downloaded cover store a 144px bitmap under the file path,
        // and every later view — the full player included — got that same
        // 144px image back from the cache. Downloaded and cached songs looked
        // soft offline while the very same song was sharp online, because
        // online each size had a key of its own.
        let key = "\(target.absoluteString)|\(decodePixels)" as NSString

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

        guard let data = await ArtFetch.data(from: target),
              let decoded = Self.downsample(data, to: size) ?? UIImage(data: data) else { return }
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


/// The mark every cover shows until its picture comes: the Blazify logo in black
/// and white, half the cover's shorter side, quiet against whatever tile the
/// cover sits on. The same as the Android app's.
struct ArtLogoMark: View {
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.5
            Image(bundleImage: "blaze_logo")
                .resizable()
                .scaledToFit()
                .saturation(0)
                .opacity(palette.dark ? 0.47 : 0.37)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}
