import SwiftUI

/// MODERN mini player, ported from MiniPlayer.kt: a 64pt rounded card whose
/// leading control is the album thumb ringed by a circular progress arc, then
/// the track info, then subscribe / add / favourite. Swipe it sideways to
/// change track; tap it to open the full player.
struct MiniPlayerView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var look = LookFeel.shared
    /// Overrides what tapping the card does. Screens presented ON TOP of the
    /// full player pass a dismiss, since the player is already behind them.
    var onOpenPlayer: (() -> Void)?
    @State private var showArtist = false
    @State private var showAddToPlaylist = false
    @State private var resolvedArtistId: String?

    var body: some View {
        if let track = player.current {
            HStack(spacing: 0) {
                playControl(track)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ink).lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(ink.opacity(0.7)).lineLimit(1)
                }
                .padding(.leading, 16)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    // ROUNDED swaps the shortcuts for transport controls, as
                    // Android's rounded design does.
                    if look.miniPlayerDesign == .rounded {
                        circleButton("backward.end.fill") { player.prev() }
                        circleButton("forward.end.fill") { player.next() }
                    } else {
                        circleButton("person") { openArtist(track) }
                        circleButton("plus") { showAddToPlaylist = true }
                    }
                    circleButton(player.isCurrentFavorite ? "heart.fill" : "heart",
                                 tint: player.isCurrentFavorite ? .red : ink) {
                        player.toggleFavorite()
                    }
                }
            }
            .padding(8)
            .frame(height: 64)
            .background(background)
            .clipShape(shape)
            .overlay(
                shape.stroke(ink.opacity(0.18), lineWidth: look.miniPlayerDesign == .flat ? 0 : 1),
            )
            .overlay(alignment: .bottom) {
                // The flat bar keeps the original thin progress line.
                if look.miniPlayerDesign == .flat {
                    GeometryReader { g in
                        Rectangle().fill(palette.accent)
                            .frame(width: g.size.width * max(player.progress, 0.002), height: 2)
                    }
                    .frame(height: 2)
                }
            }
            .shadow(color: look.miniPlayerDesign == .floating ? .black.opacity(0.35) : .clear,
                    radius: 10, y: 4)
            .padding(.horizontal, look.miniPlayerDesign == .flat ? 0 : 12)
            .contentShape(Rectangle())
            .onTapGesture { openPlayer() }
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
            .fullScreenCover(isPresented: $showArtist) {
                if let id = track.artistId ?? resolvedArtistId {
                    ArtistView(browseId: id, player: player)
                }
            }
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistSheet(track: track)
            }
        }
    }

    /// Ink that stays readable on whatever the bar is filled with.
    private var ink: Color {
        guard look.miniPlayerDesign.usesArtBackground else { return palette.onSurface }
        switch look.miniPlayerBackground {
        case .followTheme, .transparent: return palette.onSurface
        default: return .white
        }
    }

    private var shape: AnyShape {
        switch look.miniPlayerDesign {
        case .flat: AnyShape(Rectangle())
        case .modern, .rounded: AnyShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        case .floating: AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder private var background: some View {
        if !look.miniPlayerDesign.usesArtBackground {
            palette.surface
        } else {
            switch look.miniPlayerBackground {
            case .followTheme: palette.surface
            case .transparent: Color.clear
            case .pureBlack: Color.black
            case .blur:
                ZStack {
                    RemoteImage(url: player.current?.artURL(size: 240), size: 120) {
                        player.artColor
                    }
                    .blur(radius: 22)
                    Color.black.opacity(0.30)
                }
            case .gradient:
                ZStack {
                    palette.surface
                    player.artColor.opacity(0.38)
                }
            }
        }
    }

    private func openPlayer() {
        if let onOpenPlayer {
            onOpenPlayer()
        } else {
            player.showFullPlayer = true
        }
    }

    /// Open the artist, resolving the channel id by name when the row didn't
    /// carry one (search rows do; downloads and some carousels don't).
    private func openArtist(_ track: Track) {
        if track.artistId != nil {
            showArtist = true
            return
        }
        Task {
            let id = await YouTube.resolveArtistId(name: track.artist)
            await MainActor.run {
                resolvedArtistId = id
                if id != nil { showArtist = true }
            }
        }
    }

    /// 48pt play control: a progress ring around the 40pt circular album thumb.
    private func playControl(_ track: Track) -> some View {
        ZStack {
            Circle().stroke(ink.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(player.progress, 0.0001))
                .stroke(player.artColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            RemoteImage(url: track.artURL(size: 240), size: 40) { ArtPlaceholder() }
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

    private func circleButton(_ icon: String, tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        let colour = tint ?? ink
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(colour)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(ink.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
