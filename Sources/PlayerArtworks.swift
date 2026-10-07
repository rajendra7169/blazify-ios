import SwiftUI

/// Shared placeholder for missing art.
struct ArtPlaceholder: View {
    @Environment(\.palette) private var palette

    /// A cover with no picture: a quiet tile with the Blazify logo in black and
    /// white, as every cover shows while its picture loads. It was an amber
    /// gradient, which read as a picture of its own rather than as none.
    var body: some View {
        palette.onSurface.opacity(0.06)
            .overlay { ArtLogoMark() }
    }
}

/// CLASSIC — square rounded album art.
struct SquareArtwork: View {
    @ObservedObject var player: Player
    @ObservedObject private var look = LookFeel.shared
    let side: CGFloat

    var body: some View {
        // Appearance → Hide the artwork leaves the design's own background,
        // and "Fill the frame" is the crop-vs-letterbox choice.
        Group {
            if look.hidePlayerThumbnail {
                ArtPlaceholder()
            } else {
                RemoteImage(url: player.current?.artURL(size: 1080),
                            fill: look.cropAlbumArt, crossfade: true) { ArtPlaceholder() }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        // Appearance → Swipe artwork to change song. A high minimum distance
        // keeps it clear of the sheet's own swipe-down.
        .gesture(swipe, isEnabled: look.swipeThumbnail)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                if value.translation.width < -40 { _ = player.next() }
                else if value.translation.width > 40 { player.prev() }
            }
    }
}
