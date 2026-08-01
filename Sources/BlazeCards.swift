import SwiftUI
import UIKit

/// The six-colour rotation playlist cards cycle through.
enum BlazePalette {
    static let colors: [Color] = [
        Color(hex: 0xB71C5A),   // magenta
        Color(hex: 0x00838F),   // teal
        Color(hex: 0x283593),   // indigo
        Color(hex: 0x8D6E63),   // brown
        Color(hex: 0x6A1B9A),   // purple
        Color(hex: 0xEF6C00),   // deep orange
    ]

    static func color(_ index: Int) -> Color { colors[index % colors.count] }
}

/// Section title with an optional "See More", 22pt bold.
struct BlazeSectionHeader: View {
    @Environment(\.palette) private var palette
    let title: String
    var onSeeMore: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let onSeeMore {
                Button("See More", action: onSeeMore)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }
}

/// The wide gradient playlist card: artwork fills the right half and a
/// left-to-right wash of the seed colour blends it into the card.
struct BlazePlaylistCard: View {
    @Environment(\.palette) private var palette
    let title: String
    var subtitle: String = ""
    var thumbnails: [String] = []
    let seed: Color
    var aspectRatio: CGFloat = 1.6
    var icon: String?
    let action: () -> Void

    private var hasArt: Bool { thumbnails.contains { !$0.isEmpty } }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                seed

                if hasArt {
                    GeometryReader { g in
                        PlaylistArtwork(urls: thumbnails)
                            .frame(width: g.size.width * 0.5, height: g.size.height)
                            .position(x: g.size.width * 0.75, y: g.size.height / 2)
                    }
                    LinearGradient(stops: [
                        .init(color: seed, location: 0.0),
                        .init(color: seed, location: 0.45),
                        .init(color: seed.opacity(0.88), location: 0.62),
                        .init(color: seed.opacity(0.5), location: 0.78),
                        .init(color: seed.opacity(0.05), location: 1.0),
                    ], startPoint: .leading, endPoint: .trailing)
                }

                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { g in
                        // On the saturated card fill, not the page — white stays
                        // correct in both light and dark.
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .frame(width: g.size.width * 0.66, alignment: .leading)
                    }
                    .frame(height: 36)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(16)

                if let icon {
                    VStack {
                        if hasArt { Spacer().frame(height: 0) } else { Spacer() }
                        HStack {
                            Spacer()
                            Image(systemName: icon)
                                .font(.system(size: hasArt ? 20 : 30))
                                .foregroundStyle(.white.opacity(hasArt ? 1 : 0.92))
                        }
                    }
                    .padding(14)
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// One image, or a 2×2 collage when there are four or more.
struct PlaylistArtwork: View {
    let urls: [String]

    private var clean: [String] { urls.filter { !$0.isEmpty } }

    var body: some View {
        if clean.count >= 4 {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    cell(clean[0]); cell(clean[1])
                }
                HStack(spacing: 0) {
                    cell(clean[2]); cell(clean[3])
                }
            }
        } else if let first = clean.first {
            cell(first)
        } else {
            Color.black.opacity(0.15)
        }
    }

    private func cell(_ url: String) -> some View {
        RemoteImage(url: URL(string: url), size: 200) { Color.black.opacity(0.15) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

/// Rail card — square art, or a circle for artists. Its width follows the
/// Look & Feel grid-size setting.
struct BlazeMusicCard: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var look = LookFeel.shared
    let title: String
    var subtitle: String = ""
    var thumbnail: String?
    var isCircular = false
    var fallbackIcon = "music.note"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: isCircular ? .center : .leading, spacing: 0) {
                RemoteImage(url: thumbnail.flatMap { URL(string: $0) }, size: look.gridItemSize.cardWidth) {
                    palette.onSurface.opacity(0.06)
                        .overlay(Image(systemName: fallbackIcon)
                            .font(.system(size: 40))
                            .foregroundStyle(palette.onSurface.opacity(0.35)))
                }
                .frame(width: look.gridItemSize.cardWidth, height: look.gridItemSize.cardWidth)
                .clipShape(isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)))

                Spacer().frame(height: 8)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(1)
                    .multilineTextAlignment(isCircular ? .center : .leading)
                    .frame(maxWidth: isCircular ? .infinity : nil,
                           alignment: isCircular ? .center : .leading)
                if !subtitle.isEmpty {
                    Spacer().frame(height: 2)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                        .multilineTextAlignment(isCircular ? .center : .leading)
                        .frame(maxWidth: isCircular ? .infinity : nil,
                               alignment: isCircular ? .center : .leading)
                }
            }
            .frame(width: look.gridItemSize.cardWidth)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }
}

/// A square gradient tile — used by the browse categories.
struct BlazeCategoryTile: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                LinearGradient(colors: [color, color.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // Drawn on the tile's own gradient, so white regardless of theme.
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                    Text(label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A gradient card — playlists (artwork fading top-down into the seed colour)
/// and the mood tiles (seed-only), gradient stops included.
struct BlazeGradientCard: View {
    let title: String
    var subtitle: String = ""
    var thumbnail: String?
    let seed: Color
    var width: CGFloat = 160
    var height: CGFloat = 160
    var icon: String?
    let action: () -> Void

 /// Black ink on light seeds, white on dark, by luminance.
    private var ink: Color { seed.isLight ? .black : .white }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                if let thumbnail, let url = URL(string: thumbnail) {
                    // Art fills the card; the seed colour washes up from the
                    // bottom so the title always stays readable over it.
                    RemoteImage(url: url, size: width) { seed }
                        .frame(width: width, height: height)
                        .clipped()
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.3),
                        .init(color: seed.opacity(0.75), location: 0.6),
                        .init(color: seed.opacity(0.95), location: 1.0),
                    ], startPoint: .top, endPoint: .bottom)
                } else {
                    LinearGradient(colors: [seed.mixed(with: .white, 0.24), seed],
                                   startPoint: .top, endPoint: .bottom)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(ink.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                .padding(16)

                if let icon {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: icon)
                                .font(.system(size: 30))
                                .foregroundStyle(ink)
                                .shadow(color: .black.opacity(0.3), radius: 0, x: 1.5, y: 2)
                        }
                        Spacer()
                    }
                    .padding(14)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension Color {
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) > 0.55
    }

    func mixed(with other: Color, _ amount: Double) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return Color(red: Double(r1 + (r2 - r1) * t),
                     green: Double(g1 + (g2 - g1) * t),
                     blue: Double(b1 + (b2 - b1) * t))
    }
}
