import SwiftUI

/// MODERN mini player, ported from MiniPlayer.kt: a 64pt rounded card whose
/// leading control is the album thumb ringed by a circular progress arc, then
/// the track info, then subscribe / add / favourite. Swipe it sideways to
/// change track; tap it to open the full player.
struct MiniPlayerView: View {
    @ObservedObject var player: Player
    @ObservedObject private var downloads = Downloads.shared

    var body: some View {
        if let track = player.current {
            HStack(spacing: 0) {
                playControl(track)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                .padding(.leading, 16)

                Spacer(minLength: 8)

                circleButton("person") { player.showFullPlayer = true }
                circleButton(downloadIcon,
                             tint: downloads.isDownloaded(track.videoId) ? Blaze.amber : .white) {
                    downloads.toggle(track)
                }
                circleButton(player.isCurrentFavorite ? "heart.fill" : "heart",
                             tint: player.isCurrentFavorite ? .red : .white) {
                    player.toggleFavorite()
                }
            }
            .padding(8)
            .frame(height: 64)
            .background(
                ZStack {
                    Blaze.surface
                    player.artColor.opacity(0.38)
                },
            )
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1),
            )
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture { player.showFullPlayer = true }
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { g in
                        if g.translation.width < -50 {
                            player.next()
                        } else if g.translation.width > 50 {
                            player.prev()
                        }
                    },
            )
        }
    }

    /// 48pt play control: a progress ring around the 40pt circular album thumb.
    private func playControl(_ track: Track) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(player.progress, 0.0001))
                .stroke(player.artColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            RemoteImage(url: track.artURL(size: 240)) { ArtPlaceholder() }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay {
                    if !player.isPlaying {
                        ZStack {
                            Circle().fill(.black.opacity(0.4))
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                        }
                    }
                }
        }
        .frame(width: 48, height: 48)
        .contentShape(Circle())
        .onTapGesture { player.toggle() }
    }

    private var downloadIcon: String {
        guard let id = player.current?.videoId else { return "plus" }
        switch downloads.state(id) {
        case .done: return "arrow.down.circle.fill"
        case .downloading: return "hourglass"
        case .none: return "plus"
        }
    }

    private func circleButton(_ icon: String, tint: Color = .white,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
