import SwiftUI
import UIKit

/// RING design: "Now Playing" over a ring that carries the times in the gap at
/// its top, the song's name on the left with its own keys beside it, the usual
/// transport, the words as they are sung, and the same four keys every other
/// design ends with.
struct RingPlayerLayout: View {
    @ObservedObject var player: Player
    var onOpenTheme: () -> Void
    var onOpenQueue: () -> Void
    var onOpenSleep: () -> Void
    var onShowLyrics: () -> Void
    var onMore: () -> Void
    @Binding var scrub: Double?

    var body: some View {
        VStack(spacing: 0) {
            topBar

            // The ring is the only seek surface here, so the times belong to it
            // rather than to a slider underneath that says the same thing twice.
            times
            Spacer().frame(height: 6)

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.92
                SeekableAlbumRing(
                    artURL: player.current?.artURL(size: 1080),
                    progress: scrub ?? player.progress,
                    ringColor: player.artColor,
                    trackColor: .white.opacity(0.16),
                    thumbColor: player.artColor,
                ) { f in
                    scrub = nil
                    player.seek(to: f)
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 10)
            titleRow
            Spacer().frame(height: 14)
            transport
            Spacer(minLength: 10)
            RingLyricsLines(player: player, onTap: onShowLyrics)
            Spacer().frame(height: 8)
            bottomRow
            Spacer().frame(height: 10)
        }
        .foregroundStyle(.white)
    }

    // MARK: Top bar — the heading only

    private var topBar: some View {
        VStack(spacing: 2) {
            Text("Now Playing")
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
            if let from = player.current?.artist, !from.isEmpty {
                Text(from)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: The times, in the gap above the ring

    private var times: some View {
        HStack(spacing: 6) {
            Text(timeString((scrub ?? player.progress) * player.duration))
                .foregroundStyle(player.artColor)
            Text("—").foregroundStyle(.white.opacity(0.5))
            Text(player.duration > 0 ? timeString(player.duration) : "--:--")
                .foregroundStyle(.white.opacity(0.7))
        }
        .font(.system(size: 13, weight: .semibold))
        .frame(maxWidth: .infinity)
    }

    // MARK: Title on the left, its keys on the right

    private var titleRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? "")
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                Text(player.current?.artist ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ringIcon(player.isCurrentFavorite ? "heart.fill" : "heart", size: 22, box: 40,
                     tint: player.isCurrentFavorite ? .red : .white) { player.toggleFavorite() }
            ringIcon("paintpalette", size: 22, box: 40, action: onOpenTheme)
            ringIcon("ellipsis", size: 22, box: 40, action: onMore)
        }
        .padding(.horizontal, 32)
    }

    // MARK: Transport — shuffle · prev · PLAY · next · repeat

    private var transport: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ringIcon("shuffle", size: 24, box: 42,
                     tint: player.isShuffled ? Blaze.amber : .white) { player.toggleShuffle() }
            Spacer(minLength: 0)
            ringIcon("backward.end.fill", size: 34, box: 52) { player.prev() }
            Spacer(minLength: 0)
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(player.artColor)
                    // Square-ish while it plays, round while it waits, the way
                    // the other designs move.
                    .clipShape(RoundedRectangle(cornerRadius: player.isPlaying ? 22 : 33))
                    .animation(.easeOut(duration: 0.15), value: player.isPlaying)
            }
            Spacer(minLength: 0)
            ringIcon("forward.end.fill", size: 34, box: 52) { player.next() }
            Spacer(minLength: 0)
            ringIcon(player.repeatMode == .one ? "repeat.1" : "repeat", size: 24, box: 42,
                     tint: player.repeatMode != .off ? Blaze.amber : .white) { player.cycleRepeat() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
    }

    // MARK: The four keys every design ends with

    private var bottomRow: some View {
        HStack(spacing: 0) {
            key("list.bullet", "Queue", action: onOpenQueue)
            VStack(spacing: 4) {
                RoutePicker(tint: UIColor.white.withAlphaComponent(0.85),
                            activeTint: UIColor(Blaze.amber))
                    .frame(width: 26, height: 26)
                Text("AirPlay").font(.system(size: 11)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("AirPlay and Bluetooth")
            key(player.sleepActive ? "moon.zzz.fill" : "moon.zzz", sleepLabel,
                active: player.sleepActive, action: onOpenSleep)
            key("quote.bubble", "Lyrics", action: onShowLyrics)
        }
        .padding(.horizontal, 20)
    }

    private var sleepLabel: String {
        if player.sleepAtEndOfSong { return "End of song" }
        if let r = player.sleepRemaining { return timeString(r) }
        return "Sleep timer"
    }

    private func key(_ icon: String, _ label: String,
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

    private func ringIcon(_ name: String, size: CGFloat, box: CGFloat,
                          tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size))
                .foregroundStyle(tint)
                .frame(width: box, height: box)
        }
    }
}


/// Circular art wrapped in a tap/drag-seekable progress ring with a knob.
struct SeekableAlbumRing: View {
    let artURL: URL?
    let progress: Double
    let ringColor: Color
    let trackColor: Color
    let thumbColor: Color
    var stroke: CGFloat = 7        // gallery previews use 5
    var artPadding: CGFloat = 18   // gallery previews use 9
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        let shown = min(max(dragFraction ?? progress, 0), 1)

        ZStack {
            // Inset past the ring's stroke as well as the gap, so the artwork
            // sits cleanly inside the ring instead of touching it.
            // Clip BEFORE padding: padding first would make the circle the outer
            // bounds, leaving the (smaller) artwork square and untouched.
            RemoteImage(url: artURL) { ArtPlaceholder() }
                .clipShape(Circle())
                .padding(artPadding + stroke)

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let d = min(w, h) - stroke
                let r = d / 2
                let center = CGPoint(x: w / 2, y: h / 2)

                ZStack {
                    Circle()
                        .stroke(trackColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .padding(stroke / 2)
                    Circle()
                        .trim(from: 0, to: max(shown, 0.0001))
                        .stroke(ringColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(stroke / 2)

                    // Knob: white dot with a coloured core.
                    let a = (-90.0 + 360.0 * shown) * .pi / 180.0
                    let knob = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
                    Circle().fill(.white)
                        .frame(width: stroke * 1.8, height: stroke * 1.8)
                        .position(knob)
                    Circle().fill(thumbColor)
                        .frame(width: stroke * 1.2, height: stroke * 1.2)
                        .position(knob)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            dragFraction = Self.angleFraction(g.location, w, h)
                        }
                        .onEnded { g in
                            let f = Self.angleFraction(g.location, w, h)
                            dragFraction = nil
                            onSeek(f)
                        },
                )
            }
        }
    }

    /// 0 = 12 o'clock, increasing clockwise.
    private static func angleFraction(_ p: CGPoint, _ w: CGFloat, _ h: CGFloat) -> Double {
        let angle = atan2(Double(p.y - h / 2), Double(p.x - w / 2)) * 180 / .pi
        return ((angle + 90 + 360).truncatingRemainder(dividingBy: 360)) / 360
    }
}

/// The words as they are sung, on the player itself — no card, no heading, no
/// arrow. A song with no words gives the space back rather than showing an
/// empty box. Tap or swipe up for the whole song.
struct RingLyricsLines: View {
    @ObservedObject var player: Player
    let onTap: () -> Void
    @ObservedObject private var clock: PlaybackClock

    init(player: Player, onTap: @escaping () -> Void) {
        self.player = player
        self.onTap = onTap
        _clock = ObservedObject(wrappedValue: player.clock)
    }

    @State private var lines: [LyricLine] = []
    @State private var loading = true

    /// One height whatever it is showing, so the transport above it does not
    /// jump every time a line changes.
    private let areaHeight: CGFloat = 88

    var body: some View {
        Group {
            if loading {
                LyricsSkeleton()
                    .padding(.horizontal, 32)
                    .frame(height: areaHeight)
            } else if lines.isEmpty {
                // Nothing to show: give the room back to the ring.
                Color.clear.frame(height: 0)
            } else {
                VStack(spacing: 4) {
                    let i = activeIndex
                    Text(i != nil && i! > 0 ? lines[i! - 1].text : " ")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                    Text(currentLine)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(player.artColor)
                        .lineLimit(2)
                    Text(i != nil && i! + 1 < lines.count ? lines[i! + 1].text : " ")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: areaHeight)
                .padding(.horizontal, 24)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { g in if g.translation.height < -20 { onTap() } },
                )
            }
        }
        .task(id: player.current?.videoId) { await load() }
    }

    /// Before the first line has its turn there is still a song playing, so the
    /// space shows the note and what is coming rather than nothing at all.
    private var currentLine: String {
        guard let i = activeIndex else { return "♪" }
        return lines[i].text.isEmpty ? "♪" : lines[i].text
    }

    /// The genuine track length. `Track.duration` is 0 for songs parsed out of
    /// YouTube, so prefer what the player measured off the stream — the lyric
    /// providers use it to tell versions of a song apart.
    private var knownDuration: Double {
        player.duration > 0 ? player.duration : (player.current?.duration ?? 0)
    }

    private var activeIndex: Int? {
        guard !lines.isEmpty else { return nil }
        let t = player.currentTime + 0.2
        var idx: Int?
        for (i, line) in lines.enumerated() {
            if line.time <= t { idx = i } else { break }
        }
        return idx
    }

    private func load() async {
        loading = true
        lines = []
        guard let track = player.current else { loading = false; return }
        let found = await LyricsCache.shared.warm(videoId: track.videoId, title: track.title,
                                                  artist: track.artist, duration: knownDuration)
        let floor = LocalMusic.isLocal(track.videoId)
            ? Lyrics.importedFloor(artist: track.artist) : 0
        await MainActor.run {
            lines = Lyrics.best(found, floor: floor)?.lines ?? []
            loading = false
        }
    }
}

/// Three shimmering bars while lyrics load.
struct LyricsSkeleton: View {
    @State private var bright = false

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array([0.55, 0.8, 0.5].enumerated()), id: \.offset) { i, frac in
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity((bright ? 0.6 : 0.25) * (i == 1 ? 1 : 0.7)))
                        .frame(width: g.size.width * frac, height: 11)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 11)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: true)) { bright = true }
        }
    }
}
