import SwiftUI
import UIKit

/// The player. Each design is a DISTINCT full-screen layout (mirroring the
/// separate branches in the BottomSheetPlayer), not one layout with a
/// swapped picture: RING and CASSETTE own their whole chrome, while CLASSIC,
/// RECORD and FULL_ART share the standard control stack under different stages.
struct PlayerView: View {
    @ObservedObject var player: Player
    /// Ticks the transport (slider, times) — see PlaybackClock.
    @ObservedObject private var clock: PlaybackClock

    init(player: Player) {
        self.player = player
        _clock = ObservedObject(wrappedValue: player.clock)
    }
    @Environment(\.dismiss) private var dismiss

    @AppStorage("playerDesign") private var designRaw = PlayerDesign.classic.rawValue
    /// Carried into the sleep sheet, which otherwise loses the app's colours.
    @Environment(\.palette) private var palette
    @State private var scrub: Double?
    @State private var showQueue = false
    @State private var showSleep = false
    @StateObject private var videoLoader = SongVideoLoader()
    @State private var showDesign = false
    @State private var showMenu = false
    @State private var showEqualizer = false
    @State private var showLyricsSettings = false
    @State private var showLyricsTiming = false
    /// Per-song lyric offset, edited from the ⋮ and read back by the pane.
    @State private var lyricsOffset: Double = 0
    @State private var lyricsMode = false
    @State private var immersive = false
    /// Offered once, the first time the Video design meets mobile data: the cover
    /// is showing instead of the video, and this is where to say that videos may
    /// play on data after all.
    @State private var askVideoOnMobile = false
    /// Whether the video has a real frame on screen yet. Until it has, the
    /// artwork underneath is what shows — and if a picture never arrives, the
    /// artwork simply stays, the way the other designs look.
    @State private var videoShowing = false
    @ObservedObject private var prefs = PlaybackPrefs.shared
    @ObservedObject private var net = Reachability.shared

    private var design: PlayerDesign { PlayerDesign(rawValue: designRaw) ?? .classic }

 // MARK: Sheet physics
    //
    // The sheet's "value" is its visible height: expandedBound at rest, shrinking
    // 1:1 with the finger (no rubber-banding, hard-clamped at the top).

    private var expandedBound: CGFloat { UIScreen.main.bounds.height }
    /// mini-player (64) + its spacing (8) + nav bar (80)
    private var collapsedBound: CGFloat { 152 }

    private var sheetProgress: Double {
        let span = expandedBound - collapsedBound
        guard span > 0 else { return 1 }
        // Measured from where the sheet actually is, not from the drag alone —
        // otherwise arriving and leaving happen at full progress, behind a scrim
        // that is already opaque, and the travel cannot be seen at all.
        return min(max(1 - Double(sheetOffset / span), 0), 1)
    }

    /// Finger-release settle: critically damped, stiffness 1500 (SpringSpec()).
    private var settleSpring: Animation {
        .interpolatingSpring(mass: 1, stiffness: 1500, damping: 77.46)
    }

    /// Arriving and leaving.
    ///
    /// Softer and slower than the settle, because this one covers the whole
    /// height of the screen rather than the last few points of a drag: the same
    /// stiffness over that distance arrives like a slammed door.
    private var travelSpring: Animation {
        .spring(response: 0.42, dampingFraction: 0.86)
    }

    /// Where the sheet stood when this drag began, so a handover continues it.
    @State private var dragFrom: CGFloat?

    /// How far down the sheet sits — the one number, shared with the mini
    /// player so a drag that starts down there carries on up here.
    private var sheetOffset: CGFloat { player.sheetDrag }

    var body: some View {
        ZStack {
            // The cover's presentation background is CLEAR (set in RootView), so
            // the real app sits behind this. Fully opaque at rest — the gradient
            // above has a soft 0.45 middle stop and would otherwise let the app
            // show through — and fades only as the sheet is dragged down, which
 // is what reveals the app behind. the bottom-sheet reveal.
            Color.black.opacity(sheetProgress)
                .ignoresSafeArea()
                .allowsHitTesting(false)

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

                if design == .video, !lyricsMode {
                    videoArtBackground
                }

                content
                    .padding(.bottom, 16)
                    .foregroundStyle(.white)
 // Full-player content fades over progress 0.15…0.40, as.
                    .opacity(min(max((sheetProgress - 0.15) * 4, 0), 1))
                    .animation(.easeInOut(duration: 0.25), value: lyricsMode)
                    .animation(.easeInOut(duration: 0.25), value: immersive)
            }
            // NB: no clipShape here — clipping happens at the safe-area bounds,
            // which cropped the background's ignoresSafeArea and put a black band
            // under the status bar. Full-bleed matters more than the drag corners.
            .offset(y: sheetOffset)
        }
        .gesture(sheetGesture)
        // Settings → Lyrics → Hide the status bar, while lyrics are up.
        .statusBarHidden(lyricsMode && LyricsPrefs.shared.hideStatusBarFullscreen)
        .onAppear {
            // Opened by a tap: it is sitting at zero, so put it off the bottom
            // and let it travel up. Opened by a drag from the mini player: the
            // finger already placed it somewhere and owns it until let go.
            if player.sheetDrag == 0 {
                player.sheetDrag = expandedBound
                withAnimation(travelSpring) { player.sheetDrag = 0 }
            }
            // Settings → Player → Keep the screen on.
            UIApplication.shared.isIdleTimerDisabled = PlaybackPrefs.shared.keepScreenOn
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .fullScreenCover(isPresented: $showDesign) { PlayerDesignPicker(player: player) }
        // Full screen, as on Android. A sheet left the queue sitting in a card
        // with the player showing above it, which makes a list of fifty songs
        // feel like a note about the queue rather than the queue itself.
        .fullScreenCover(isPresented: $showQueue) {
            QueueView(player: player).environment(\.palette, palette)
        }
        .sheet(isPresented: $showEqualizer) {
            NavigationStack { EqualizerView(player: player) }
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showLyricsTiming) {
            LyricsTimingSheet(offset: $lyricsOffset) {
                LyricsOffsets.save(lyricsOffset, for: player.current?.videoId ?? "")
            }
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $showLyricsSettings) {
            NavigationStack { LyricsSettingsView() }
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showSleep) {
            SleepTimerView(player: player).environment(\.palette, palette)
        }
        .sheet(isPresented: $showMenu) {
            PlayerMenuSheet(
                player: player,
                onQueue: { showQueue = true },
                onSleep: { showSleep = true },
                onLyrics: { lyricsMode = true },
                onLyricsSettings: { showLyricsSettings = true },
                onLyricsTiming: {
                    lyricsOffset = LyricsOffsets.load(for: player.current?.videoId ?? "")
                    showLyricsTiming = true
                },
                onEqualizer: { showEqualizer = true },
            )
        }
    }

    /// The sheet drag: 1:1 with the finger, then a velocity/position classifier —
 /// never a decay fling (performFling uses velocity only to
    /// choose a target, and the spring gets no initial velocity).
    private var sheetGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                // Measured from wherever the sheet already is, not from the top.
                // A drag that began on the mini player hands over to this one the
                // moment the cover appears, and starting from zero each time
                // would snap the sheet shut under the finger that was opening it.
                if dragFrom == nil { dragFrom = player.sheetDrag }
                player.sheetDrag = max(0, (dragFrom ?? 0) + g.translation.height)
            }
            .onEnded { g in
                dragFrom = nil
                let vy = g.velocity.height                  // px/s, positive = downward
                let value = expandedBound - player.sheetDrag  // the sheet's visible height
                let midpoint = (expandedBound - collapsedBound) / 2

                if vy < -250 {                              // flicked up → expand
                    springBack()
                } else if vy > 250 {                        // flicked down → collapse
                    close()
                } else if value > midpoint {
                    springBack()
                } else {
                    close()
                }
            }
    }

    private func springBack() {
        withAnimation(settleSpring) { player.sheetDrag = 0 }
    }

    /// Put the sheet down the way it came up.
    ///
    /// Dismissing outright hands a sheet that is halfway down the screen to a
    /// system animation that knows nothing about where the finger left it, and
    /// the two together read as a cut. This carries it the rest of the way
    /// first, and lets the cover go once there is nothing left to see.
    private func close() {
        withAnimation(travelSpring) { player.sheetDrag = expandedBound }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            dismiss()
            // Back to zero once it is out of sight, so the next tap opens from
            // the bottom rather than from wherever this one ended.
            player.sheetDrag = 0
        }
    }

    // MARK: Layout dispatch

    @ViewBuilder private var content: some View {
        if lyricsMode {
            standardLayout {
                LyricsPane(player: player, immersive: immersive)
                    .transition(.opacity)
            }
        } else {
            switch design {
            case .ring:
                RingPlayerLayout(
                    player: player,
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
                    clock: clock,
                    onLyrics: { lyricsMode = true },
                    onQueue: { showQueue = true },
                    onSleep: { showSleep = true },
                    onTheme: { showDesign = true },
                    onMore: { showMenu = true },
                )
            case .classic:
                standardLayout {
                    SquareArtwork(player: player, side: stageHeight)
                }
            case .record:
                standardLayout {
                    VinylTurntableView(
                        artURL: player.current?.artURL(size: 1080),
                        isPlaying: player.isPlaying,
                        progress: player.progress,
                        fallback: Blaze.gradient,
                    )
                    .frame(height: stageHeight)
                    .padding(.horizontal, 32)
                }
            case .fullArt, .video:
                standardLayout { Color.clear.frame(height: stageHeight) }
            }
        }
    }

    /// Header · stage · title+progress · transport · bottom row.
    /// How tall a design's stage is.
    ///
    /// Classic's artwork set this by accident and the others did not have it:
    /// Full Art, Video and Record handed the layout something that grew to fill
    /// the screen, so every spacer below collapsed to its minimum and the words,
    /// the bar and the keys ended up piled together. One height for all of them
    /// puts those rows in the same places whichever design is on.
    private var stageHeight: CGFloat { min(UIScreen.main.bounds.width - 96, 320) }

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

    /// The song's own video behind the player, muted and in step. The still
    /// artwork stands in while it is being looked up, or when there is none.
    @ViewBuilder private var videoArtBackground: some View {
        GeometryReader { geo in
            ZStack {
                // The artwork fills the same place, always: while the video is
                // being found, while it is loading, and for a song that has none.
                // It is the cover underneath — never the app's own flame, which is
                // what a song's picture is not.
                RemoteImage(url: player.current?.artURL(size: 1280)) {
                    Color.black
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                if let v = videoLoader.video {
                    VideoArtView(video: v,
                                 position: player.currentTime,
                                 isPlaying: player.isPlaying,
                                 songLength: player.duration,
                                 onTrouble: { videoLoader.trouble($0) },
                                 onFirstFrame: { videoShowing = true })
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(videoShowing ? 1 : 0)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: videoShowing)
            // A new song is the artwork again until its own picture arrives, so
            // skipping never leaves the song before it playing on the screen.
            .onChange(of: player.current?.videoId) { videoShowing = false }
            .onChange(of: videoLoader.video) { if videoLoader.video == nil { videoShowing = false } }
            // The picture is left alone down to the middle of the screen and only
            // then fades into the page the controls sit on — the same stage fade
            // the Android Video design uses. Dimming it from the top, as the still
            // artwork is dimmed, was throwing a veil over the one design whose
            // whole point is the picture.
            .overlay(
                // Android gives the picture the top 70% of the screen and fades it
                // out over the lower half of that — so it is clear at the top, gone
                // by the progress bar, and the controls stand on solid black. These
                // are those same places measured against the whole screen.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.30),
                    .init(color: .black.opacity(0.85), location: 0.55),
                    .init(color: .black, location: 0.66),
                    .init(color: .black, location: 1.0),
                ], startPoint: .top, endPoint: .bottom),
            )
        }
        .ignoresSafeArea()
        .task(id: player.current?.videoId) { loadVideo() }
        .onChange(of: prefs.videoOnMobile) { loadVideo() }
        .onChange(of: net.isUnmetered) { loadVideo() }
        .onAppear {
            loadVideo()
            offerVideoOnMobile()
        }
        .alert("Videos on mobile data", isPresented: $askVideoOnMobile) {
            Button("Not now", role: .cancel) {}
            Button("Play videos") { prefs.videoOnMobile = true }
        } message: {
            Text("The Video player fetches a picture as well as the song, which costs far "
                 + "more data. On mobile data it shows the cover instead. You can change "
                 + "this any time in Settings › Player and audio.")
        }
    }

    /// Asked once, and only where it matters: the Video design, on a connection
    /// that charges by the megabyte, with the switch still off.
    private func offerVideoOnMobile() {
        guard design == .video, !net.isUnmetered, !prefs.videoOnMobile else { return }
        let key = "videoOnMobileAsked"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        askVideoOnMobile = true
    }

    /// A video is far heavier than a picture, so it waits for an unmetered
    /// connection unless it has been asked for on mobile data.
    private func loadVideo() {
        let allowed = Reachability.shared.isUnmetered || PlaybackPrefs.shared.videoOnMobile
        // What Android asks for. A taller picture buys detail nobody can see at
        // this size and costs seconds before the first frame.
        let height = Reachability.shared.isUnmetered ? 480 : 360
        videoLoader.load(for: player.current, allowed: allowed, maxHeight: height)
        // And open the one after it, so skipping lands on a picture.
        videoLoader.prepareNext(player.upNext, allowed: allowed, maxHeight: height)
    }

    private var fullArtBackground: some View {
        GeometryReader { geo in
            RemoteImage(url: player.current?.artURL(size: 1280)) { Color.black }
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

    @ViewBuilder private var header: some View {
        ZStack {
            // The lyrics page is the words and nothing else; "Now Playing" over
            // them is the one heading that says nothing you cannot see.
            VStack(spacing: 4) {
                if !lyricsMode {
                    Text("Now Playing")
                        .font(.system(size: 16, weight: design == .fullArt ? .bold : .semibold))
                        .shadow(color: design == .fullArt ? .black.opacity(0.7) : .clear,
                                radius: 3, y: 2)
                    if let from = player.current?.artist, !from.isEmpty {
                        Text(from)
                            .font(.system(size: 13, weight: .medium))
                            .opacity(0.8)
                            .lineLimit(1)
                            .shadow(color: design == .fullArt ? .black.opacity(0.7) : .clear,
                                    radius: 3, y: 2)
                    }
                }
            }
            .padding(.horizontal, 48)

        }
    }

    // MARK: Title + progress

    private var titleAndProgress: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // On the lyrics page the artwork is nowhere else on screen, so
                // the title carries a small square of it — the way the Android
                // lyrics screen does.
                if lyricsMode {
                    RemoteImage(url: player.current?.artURL(size: 120), size: 44) {
                        ArtPlaceholder()
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(player.current?.title ?? "")
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                    Text(player.current?.artist ?? "")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    // Only on the design that promised a picture, and only while
                    // there is none: the reason, in place of a mystery.
                    if design == .video, videoLoader.video == nil, let note = videoLoader.note {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
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

            // A broadcast is wherever it is right now: it gets a LIVE mark
            // instead of a bar to drag and two times that do not exist.
            if player.isCurrentLive {
                LiveBadge()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            } else {
                SlimSlider(
                    value: Binding(get: { scrub ?? player.progress }, set: { scrub = $0 }),
                    active: player.artColor,
                    duration: player.duration,
                    isPlaying: player.isPlaying,
                ) { v in
                    player.seek(to: v)
                    scrub = nil
                }
                .padding(.horizontal, 32)
                // The bar follows the clock exactly; it must never inherit an
                // animation from whatever is happening around it — the screen
                // opening, a design changing — or it slides to the position
                // instead of being at it.
                .transaction { $0.animation = nil }
                // A drag left half-finished belongs to the song it was dragging.
                .onChange(of: player.current?.videoId) { scrub = nil }

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
    }

    // MARK: Transport — shuffle · prev · PLAY · next · repeat

    private var transport: some View {
        HStack(spacing: 0) {
            sideButton("shuffle", active: player.isShuffled,
                       label: player.isShuffled ? "Shuffle on" : "Shuffle off") {
                player.toggleShuffle()
            }
            sideButton("backward.end.fill", label: "Previous song") { player.prev() }

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
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            sideButton("forward.end.fill", label: "Next song") { _ = player.next() }
            sideButton(player.repeatMode == .one ? "repeat.1" : "repeat",
                       active: player.repeatMode != .off,
                       label: repeatLabel) { player.cycleRepeat() }
        }
        .padding(.horizontal, 32)
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: return "Repeat off"
        case .all: return "Repeat all"
        case .one: return "Repeat one"
        }
    }

    private func sideButton(_ icon: String, active: Bool = false, label: String = "",
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(active ? Blaze.amber : .white)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(label)
    }

    // MARK: Bottom row

    private var bottomRow: some View {
        HStack(spacing: 0) {
            bottomButton("list.bullet", "Queue") { showQueue = true }
            airPlayButton
            bottomButton(player.sleepActive ? "moon.zzz.fill" : "moon.zzz",
                         sleepLabel, active: player.sleepActive) { showSleep = true }
            bottomButton("quote.bubble", "Lyrics", active: lyricsMode) {
                lyricsMode.toggle()
                if !lyricsMode { immersive = false }
            }
        }
        .padding(.horizontal, 20)
    }

    /// Same shape as the others, but the tappable part is the system's own
    /// button — it draws its glyph inside whatever frame it's given, and it
    /// turns amber by itself once audio is somewhere else.
    private var airPlayButton: some View {
        VStack(spacing: 4) {
            RoutePicker(tint: UIColor.white.withAlphaComponent(0.85),
                        activeTint: UIColor(Blaze.amber))
                .frame(width: 26, height: 26)
            Text("AirPlay").font(.system(size: 11)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(maxWidth: .infinity)
        .accessibilityLabel("AirPlay and Bluetooth")
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
