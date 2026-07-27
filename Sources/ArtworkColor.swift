import UIKit
import SwiftUI

/// Album-art color extraction for the player's dynamic gradient background.
/// Blaze amber is only the fallback seed (see project brief) — the real seed is
/// pulled from the current artwork.
extension UIImage {
    /// Average color of the whole image (fast, via CIAreaAverage).
    var averageColor: UIColor? {
        guard let input = CIImage(image: self) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ])
        guard let output = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255,
                       blue: CGFloat(bitmap[2]) / 255, alpha: 1)
    }

    /// A saturated, mid-brightness seed for the top of the player gradient —
    /// vivid enough to read as "the song's color", clamped so white text stays legible.
    var gradientSeed: Color {
        guard let avg = averageColor else { return Blaze.amber }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        avg.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let boosted = UIColor(hue: h,
                              saturation: min(s * 1.4, 1.0),
                              brightness: min(max(b, 0.38), 0.62),
                              alpha: 1)
        return Color(boosted)
    }
}
