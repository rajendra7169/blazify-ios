import SwiftUI
import UIKit

/// The player. Each design is a DISTINCT full-screen layout (mirroring the
/// separate branches in Android's BottomSheetPlayer), not one layout with a
/// swapped picture: RING and CASSETTE own their whole chrome, while CLASSIC,
/// RECORD and FULL_ART share the standard control stack under different stages.
struct PlayerView: View {
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    @AppStorage("playerDesign") private var designRaw = PlayerDesign.classic.rawValue
    @State private var scrub: Double?
    @State private var showQueue = false
    @State private var showSleep = false
    @State private var showDesign = false
    @State private var showMenu = false
    @State private var lyricsMode = false
    @State private var immersive = false
    @State private var dragOffset: CGFloat = 0

    private var design: PlayerDesign { PlayerDesign(rawValue: designRaw) ?? .classic }

    // MARK: Sheet physics (ported from BottomSheet.kt)
    //
    // The sheet's "value" is its visible height: expandedBound at rest, shrinking
    // 1:1 with the finger (no rubber-banding, hard-clamped at the top).

    private var expandedBound: CGFloat { UIScreen.main.bounds.height }
    /// mini-player (64) + its spacing (8) + nav bar (80)
    private var collapsedBound: CGFloat { 152 }

    private var sheetProgress: Double {
        let span = expandedBound - collapsedBound
        guard span > 0 else { return 1 }
        return min(max(1 - Double(dragOffset / span), 0), 1)
    }

    /// Finger-release settle: critically damped, stiffness 1500 (SpringSpec()).
    private var settleSpring: Animation {
        .interpolatingSpring(mass: 1, stiffness: 1500, damping: 77.46)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [player.artColor, player.artColor.opacity(0.45), .black],
                startPoint: .top, endPoint: .bottom,
            )
            .overlay(Color.black.opacity(0.2))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: player.artColor)

            if design == .fullArt, !lyricsMode {
                fullArtBackground
            }

            content
                .padding(.bottom, 16)
                .foregroundStyle(.white)
                // Full-player content fades over progress 0.15…0.40, as in BottomSheet.kt.
                .opacity(min(max((sheetProgress - 0.15) * 4, 0), 1))
                .animation(.easeInOut(duration: 0.25), value: lyricsMode)
                .animation(.easeInOut(duration: 0.25), value: immersive)
        }
        // NB: no clipShape here — clipping happens at the safe-area bounds, which
        // cropped the background's ignoresSafeArea and put a black band under the
        // status bar. Full-bleed matters more than the 16pt drag corners.
        .offset(y: dragOffset)
        .gesture(sheetDrag)
        .onAppear { dragOffset = 0 }
        .fullScreenCover(isPresented: $showDesign) { PlayerDesignPicker(player: player) }
        .sheet(isPresented: $showQueue) { QueueView(player: player) }
        .sheet(isPresented: $showSleep) { SleepTimerView(player: player) }
        .sheet(isPresented: $showMenu) {
            PlayerMenuSheet(
                player: player,
                onQueue: { showQueue = true },
                onSleep: { showSleep = true },
                onLyrics: { lyricsMode = true },
            )
        }
    }

    /// The sheet drag: 1:1 with the finger, then a velocity/position classifier —
    /// never a decay fling (performFling in BottomSheet.kt uses velocity only to
    /// choose a target, and the spring gets no initial velocity).
    private var sheetDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                dragOffset = max(0, g.translation.height)   // hard-clamped at the top
            }
            .onEnded { g in
                let vy = g.velocity.height                  // px/s, positive = downward
                let value = expandedBound - dragOffset      // the sheet's visible height
                let midpoint = (expandedBound - collapsedBound) / 2

                if vy < -250 {                              // flicked up → expand
                    springBack()
                } else if vy > 250 {                        // flicked down → collapse
                    dismiss()
                } else if value > midpoint {
                    springBack()
                } else {
                    dismiss()
                }
            }
    }

    private func springBack() {
        withAnimation(settleSpring) { dragOffset = 0 }
    }

    // MARK: Layout dispatch

    @ViewBuilder private var content: some View {
        if lyricsMode {
            standardLayout { LyricsPane(player: player).transition(.opacity) }
        } else {
            switch design {
            case .ring:
                RingPlayerLayout(
                    player: player,
                    onCollapse: { dismiss() },
                    onOpenTheme: { showDesign = true },
                    onOpenQueue: { showQueue = true },
                    onOpenSleep: { showSleep = true },
                    onShowLyrics: { lyricsMode = true },
                    onMore: { showMenu = true },
                    scrub: $scrub,
                )
            case .cassette:
                CassettePlayerLayout(
                    player: player,
                    onLyrics: { lyricsMode = true },
                    onQueue: { showQueue = true },
                    onSleep: { showSleep = true },
                    onTheme: { showDesign = true },
                    onMore: { showMenu = true },
                )
            case .classic:
                standardLayout {
                    SquareArtwork(player: player, side: min(UIScreen.main.bounds.width - 96, 320))
                }
            case .record:
                standardLayout {
                    VinylTurntableView(
                        artURL: player.current?.artURL(size: 1080),
                        isPlaying: player.isPlaying,
                        progress: player.progress,
                        fallback: Blaze.gradient,
                    )
                    .padding(.horizontal, 32)
                }
            case .fullArt:
                standardLayout { Color.clear }
            }
        }
    }

    /// Header · stage · title+progress · transport · bottom row.
    @ViewBuilder private func standardLayout<Stage: View>(@ViewBuilder stage: () -> Stage) -> some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 12)
            stage()
            Spacer(minLength: 18)
            titleAndProgress
            if !immersive {
                Spacer(minLength: 28)
                transport
                Spacer(minLength: 22)
                bottomRow
            } else {
                Spacer(minLength: 16)
            }
        }
        .padding(.top, 6)
    }

    // MARK: Full-art background (5-stop scrim, ported exactly)

    private var fullArtBackground: some View {
        GeometryReader { geo in
            RemoteImage(url: player.current?.artURL(size: 1280)) { ArtPlaceholder() }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.40), location: 0.0),
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.55), location: 0.60),
                        .init(color: .black.opacity(0.80), location: 0.80),
                        .init(color: .black.opacity(0.95), location: 1.0),
                    ], startPoint: .top, endPoint: .bottom),
                )
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            VStack(spacing: 4) {
                Text("Now Playing")
                    .font(.system(size: 16, weight: design == .fullArt ? .bold : .semibold))
                    .shadow(color: design == .fullArt ? .black.opacity(0.7) : .clear, radius: 3, y: 2)
                if let from = player.current?.artist, !from.isEmpty {
                    Text(from)
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.8)
                        .lineLimit(1)
                        .shadow(color: design == .fullArt ? .black.opacity(0.7) : .clear, radius: 3, y: 2)
                }
            }
            .padding(.horizontal, 48)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: Title + progress

    private var titleAndProgress: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.current?.title ?? "")
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                    Text(player.current?.artist ?? "")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                if lyricsMode {
                    Button { immersive.toggle() } label: {
                        Image(systemName: immersive
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                } else {
                    Button { player.toggleFavorite() } label: {
                        Image(systemName: player.isCurrentFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 26))
                            .foregroundStyle(player.isCurrentFavorite ? .red : .white)
                    }
                }

                if !immersive {
                    Button { showDesign = true } label: {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(Color.white)
                            .clipShape(Circle())
                    }

                    Button { showMenu = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 32)

            if let err = player.lastError {
                Text(err)
                    .font(.caption2).foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32).padding(.top, 8)
            }

            Spacer().frame(height: 24)

            SlimSlider(
                value: Binding(get: { scrub ?? player.progress }, set: { scrub = $0 }),
                active: player.artColor,
            ) { v in
                player.seek(to: v)
                scrub = nil
            }
            .padding(.horizontal, 32)

            HStack {
                Text(timeString((scrub ?? player.progress) * player.duration))
                Spacer()
                Text(timeString(player.duration))
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 36)
            .padding(.top, 6)
        }
    }

    // MARK: Transport — shuffle · prev · PLAY · next · repeat

    private var transport: some View {
        HStack(spacing: 0) {
            sideButton("shuffle", active: player.isShuffled) { player.toggleShuffle() }
            sideButton("backward.end.fill") { player.prev() }

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 72, height: 72)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: player.isPlaying ? 24 : 36))
                    .animation(.linear(duration: 0.09), value: player.isPlaying)
            }
            .padding(.horizontal, 8)

            sideButton("forward.end.fill") { player.next() }
            sideButton(player.repeatMode == .one ? "repeat.1" : "repeat",
                       active: player.repeatMode != .off) { player.cycleRepeat() }
        }
        .padding(.horizontal, 32)
    }

    private func sideButton(_ icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(active ? Blaze.amber : .white)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Bottom row

    private var bottomRow: some View {
        HStack(spacing: 0) {
            bottomButton("list.bullet", "Queue") { showQueue = true }
            bottomButton(player.sleepActive ? "moon.zzz.fill" : "moon.zzz",
                         sleepLabel, active: player.sleepActive) { showSleep = true }
            bottomButton("quote.bubble", "Lyrics", active: lyricsMode) {
                lyricsMode.toggle()
                if !lyricsMode { immersive = false }
            }
        }
        .padding(.horizontal, 20)
    }

    private func bottomButton(_ icon: String, _ label: String,
                              active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 11)).lineLimit(1)
            }
            .foregroundStyle(active ? Blaze.amber : .white.opacity(0.85))
            .frame(maxWidth: .infinity)
        }
    }

    private var sleepLabel: String {
        if player.sleepAtEndOfSong { return "End of song" }
        if let r = player.sleepRemaining { return timeString(r) }
        return "Sleep timer"
    }

}
