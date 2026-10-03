import SwiftUI

/// MODERN mini player: a 64pt rounded card whose
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
    /// Only the ring reads this, but the view is small — observing is cheap.
    @ObservedObject private var clock: PlaybackClock
    @State private var showArtist = false
    /// How far the mini player has been dragged down, while a finger is on it.
    @State private var dragDown: CGFloat = 0
    @State private var showAddToPlaylist = false
    @State private var resolvedArtistId: String?

    init(player: Player, onOpenPlayer: (() -> Void)? = nil) {
        self.player = player
        self.onOpenPlayer = onOpenPlayer
        _clock = ObservedObject(wrappedValue: player.clock)
    }

    var body: some View {
        if let track = player.current {
            HStack(spacing: 0) {
                if look.miniPlayerDesign == .flat {
                    RemoteImage(url: track.artURL(size: 144), size: 48) { ArtPlaceholder() }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    playControl(track)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ink).lineLimit(1)
                    HStack(spacing: 6) {
                        if player.liveBroadcasts.contains(track.videoId) {
                            LiveBadge()
                        }
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(ink.opacity(0.7)).lineLimit(1)
                    }
                }
                .padding(.leading, 16)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    switch look.miniPlayerDesign {
                    case .flat:
                        // LegacyMiniPlayer: plain play/pause and skip-next.
                        plainButton(player.isPlaying ? "pause.fill" : "play.fill") {
                            player.toggle()
                        }
                        plainButton("forward.end.fill") { player.next() }
                    case .rounded:
                        // MiniPlayerTransportCluster: prev · filled play · next.
                        plainButton("backward.end.fill", size: 18) { player.prev() }
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(palette.onAccent)
                                .frame(width: 40, height: 40)
                                .background(palette.accent)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        plainButton("forward.end.fill", size: 18) { player.next() }
                    default:
                        circleButton("person") { openArtist(track) }
                        circleButton("plus") { showAddToPlaylist = true }
                        circleButton(player.isCurrentFavorite ? "heart.fill" : "heart",
                                     tint: player.isCurrentFavorite ? .red : ink) {
                            player.toggleFavorite()
                        }
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
                // LegacyMiniPlayer's 2pt progress line: full-width track with
                // the accent fill on top.
                if look.miniPlayerDesign == .flat {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(ink.opacity(0.2))
                            Rectangle().fill(palette.accent)
                                .frame(width: g.size.width * max(player.progress, 0.002))
                        }
                    }
                    .frame(height: 2)
                }
            }
            .shadow(color: look.miniPlayerDesign == .floating ? .black.opacity(0.35) : .clear,
                    radius: 10, y: 4)
            .padding(.horizontal, look.miniPlayerDesign == .flat ? 0 : 12)
            .contentShape(Rectangle())
            .onTapGesture { openPlayer() }
            .offset(y: dragDown)
            // Simultaneous, not exclusive: attached plainly, the drag enters
            // arbitration against the tap and the first tap is spent deciding
            // between them rather than opening anything. A tap cannot start a
            // drag that needs twenty points of travel, so letting both watch
            // costs nothing.
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { g in
                        guard abs(g.translation.height) > abs(g.translation.width) else { return }
                        if g.translation.height < 0 {
                            // Upward: the full player comes with the finger. It
                            // is presented straight away, sitting a screen-height
                            // down, and rises as far as the thumb has travelled —
                            // so the page behind dims and the player fades in
                            // exactly as they do in reverse on the way out,
                            // rather than the swipe being a switch that fires at
                            // the end of itself.
                            dragDown = 0
                            let screen = UIScreen.main.bounds.height
                            if !player.showFullPlayer {
                                player.draggingSheet = true
                                player.sheetDrag = screen
                                player.showFullPlayer = true
                            }
                            player.sheetDrag = max(0, screen + g.translation.height)
                        } else {
                            // Downward: follows the finger, so the swipe that
                            // puts the player away looks like it is putting it
                            // away.
                            dragDown = g.translation.height
                        }
                    }
                    .onEnded { g in
                        let vertical = abs(g.translation.height) > abs(g.translation.width)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragDown = 0 }
                        if vertical, player.showFullPlayer, g.translation.height < 0 {
                            // The player is already up and following the finger;
                            // all that is left is deciding where it settles.
                            player.draggingSheet = false
                            let screen = UIScreen.main.bounds.height
                            let far = g.translation.height < -90 || g.velocity.height < -300
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                player.sheetDrag = far ? 0 : screen
                            }
                            if !far {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                                    player.showFullPlayer = false
                                    player.sheetDrag = 0
                                }
                            }
                        } else if vertical {
                            // Down puts it away — the gesture the Android sheet
                            // answers to as well.
                            if g.translation.height < -40 {
                                openPlayer()
                            } else if g.translation.height > 60 {
                                player.dismissPlayback()
                            }
                        } else if g.translation.width < -50 {
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
        case .flat:
            AnyShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        case .modern, .rounded:
            AnyShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        case .floating:
            AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// A bare icon button, as the flat design's transport uses.
    private func plainButton(_ icon: String, size: CGFloat = 20,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(ink)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.label(for: icon))
    }

    /// VoiceOver reads an SF Symbol name as gibberish; name the action instead.
    static func label(for icon: String) -> String {
        switch icon {
        case "play.fill": return "Play"
        case "pause.fill": return "Pause"
        case "forward.end.fill", "forward.fill": return "Next song"
        case "backward.end.fill", "backward.fill": return "Previous song"
        case "heart", "heart.fill": return "Favourite"
        case "text.badge.plus": return "Add to queue"
        case "person": return "View artist"
        case "plus": return "Add to playlist"
        default: return ""
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
        .accessibilityLabel(Self.label(for: icon))
    }
}
