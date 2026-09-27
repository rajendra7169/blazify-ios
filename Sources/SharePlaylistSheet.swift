import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Hand a playlist of your own to somebody: a link to send, or a square to point
/// a camera at when they are standing next to you.
struct SharePlaylistSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let name: String
    let songIds: [String]

    @State private var copied = false

    private var link: String { PlaylistLink.build(name: name, songIds: songIds) }

    /// Songs past the cap are left out, and it is better to say so than to let
    /// someone hand over a playlist quietly missing its tail.
    private var trimmed: Int { max(songIds.count - PlaylistLink.maxSongs, 0) }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 26))
                    .foregroundStyle(palette.accent)
                Text("Share playlist")
                    .font(.blaze(22, .bold))
                    .foregroundStyle(palette.onSurface)
                Spacer(minLength: 0)
            }

            if let qr = qrImage {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .padding(12)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Text("Anyone with Blazify can open this and keep the playlist. The songs travel in the link itself, not through any website.")
                .font(.blaze(13))
                .foregroundStyle(palette.onSurfaceVariant)
                .multilineTextAlignment(.center)

            if trimmed > 0 {
                Text("The first \(PlaylistLink.maxSongs) songs are included; \(trimmed) did not fit.")
                    .font(.blaze(12))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = link
                    copied = true
                } label: {
                    Text(copied ? "Copied" : "Copy link")
                        .font(.blaze(15, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(palette.onSurface.opacity(0.10))
                        .foregroundStyle(palette.onSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                ShareLink(item: link) {
                    Text("Share")
                        .font(.blaze(15, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(palette.accent)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .presentationBackground(.regularMaterial)
        .presentationDetents([.medium, .large])
    }

    /// The link as a square. Low correction, because the link is long and every
    /// extra level of recovery makes the squares smaller and harder to read.
    private var qrImage: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
