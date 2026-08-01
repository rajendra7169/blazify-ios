import SwiftUI

/// Pulsing placeholder blocks used while a screen loads, matching the
/// ShimmerHost: a 700ms alpha pulse between 0.25 and 0.6.
struct SkeletonBox: View {
    var width: CGFloat?
    var height: CGFloat = 14
    var corner: CGFloat = 6

    @Environment(\.palette) private var palette
    @State private var bright = false

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(palette.onSurface.opacity(bright ? 0.16 : 0.07))
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    bright = true
                }
            }
    }
}

/// Placeholder for a track row: art + title + artist.
struct SkeletonTrackRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonBox(width: 52, height: 52, corner: 8)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBox(width: 170, height: 13)
                SkeletonBox(width: 110, height: 11)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// Placeholder list of track rows.
struct SkeletonTrackList: View {
    var rows = 8

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<rows, id: \.self) { _ in
                SkeletonTrackRow()
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Placeholder for a horizontal card rail (title + row of cards).
struct SkeletonRail: View {
    var cardSize: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBox(width: 150, height: 20).padding(.horizontal, 16)
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBox(width: cardSize, height: cardSize, corner: 12)
                        SkeletonBox(width: cardSize * 0.8, height: 12)
                        SkeletonBox(width: cardSize * 0.55, height: 10)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }
}

/// Placeholder 2-column grid of square tiles.
struct SkeletonGrid: View {
    var count = 6

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBox(height: 150, corner: 12)
                    SkeletonBox(width: 110, height: 12)
                    SkeletonBox(width: 70, height: 10)
                }
            }
        }
        .padding(16)
    }
}
