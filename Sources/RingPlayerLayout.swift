import SwiftUI

/// RING design — ported from RingPlayerLayout.kt: its own top bar, a draggable
/// progress ring around circular art, queue·title·heart row, the transport in
/// repeat · prev · PLAY · next · shuffle order, then a sleep/more row and the
/// "Show Lyrics" card pinned to the bottom.
struct RingPlayerLayout: View {
    @ObservedObject var player: Player
    var onCollapse: () -> Void
    var onOpenTheme: () -> Void
    var onOpenQueue: () -> Void
    var onOpenSleep: () -> Void
    var onShowLyrics: () -> Void
    var onMore: () -> Void
    @Binding var scrub: Double?

    var body: some View {
        VStack(spacing: 0) {
            topBar

            // Ring stage.
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.92
                SeekableAlbumRing(
                    artURL: player.current?.artURL(size: 1080),
                    progress: player.progress,
                    ringColor: player.artColor,
                    trackColor: .white.opacity(0.16),
                    thumbColor: player.artColor,
                ) { f in
                    player.seek(to: f)
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 8)
            infoRow
            Spacer().frame(height: 6)

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
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 36)

            Spacer().frame(height: 10)
            transport
            Spacer(minLength: 12)
            bottomOverlay
        }
        .foregroundStyle(.white)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            ringIcon("chevron.down", size: 28, box: 46, action: onCollapse)
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
            .padding(.horizontal, 8)
            ringIcon("paintpalette", size: 24, box: 42, action: onOpenTheme)
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: Queue · title/artist · favourite

    private var infoRow: some View {
        HStack(spacing: 0) {
            ringIcon("list.bullet", size: 26, box: 44, action: onOpenQueue)
            VStack(spacing: 2) {
                Text(player.current?.title ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Text(player.current?.artist ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            Button { player.toggleFavorite() } label: {
                Image(systemName: player.isCurrentFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 26))
                    .foregroundStyle(player.isCurrentFavorite ? .red : .white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: Transport — repeat · prev · PLAY · next · shuffle

    private var transport: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ringIcon(player.repeatMode == .one ? "repeat.1" : "repeat", size: 24, box: 42,
                     tint: player.repeatMode != .off ? Blaze.amber : .white) { player.cycleRepeat() }
            Spacer(minLength: 0)
            ringIcon("backward.end.fill", size: 34, box: 52) { player.prev() }
            Spacer(minLength: 0)
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(player.artColor)
                    .clipShape(Circle())
            }
            Spacer(minLength: 0)
            ringIcon("forward.end.fill", size: 34, box: 52) { player.next() }
            Spacer(minLength: 0)
            ringIcon("shuffle", size: 24, box: 42,
                     tint: player.isShuffled ? Blaze.amber : .white) { player.toggleShuffle() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
    }

    // MARK: Bottom overlay (sleep · more, then the lyrics card)

    private var bottomOverlay: some View {
        VStack(spacing: 8) {
            HStack {
                ringIcon(player.sleepActive ? "moon.zzz.fill" : "moon.zzz", size: 24, box: 42,
                         tint: player.sleepActive ? Blaze.amber : .white, action: onOpenSleep)
                Spacer()
                ringIcon("ellipsis", size: 24, box: 42, action: onMore)
            }
            .padding(.horizontal, 32)

            RingLyricsCard(player: player, onTap: onShowLyrics)
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

/// The bottom "Show Lyrics" card — previous / current / next synced line.
struct RingLyricsCard: View {
    @ObservedObject var player: Player
    let onTap: () -> Void

    @State private var lines: [LyricLine] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Show Lyrics")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Image(systemName: "chevron.up").font(.system(size: 18))
            }
            Spacer().frame(height: 10)

            if loading {
                LyricsSkeleton()
            } else if let i = activeIndex {
                VStack(spacing: 4) {
                    Text(i > 0 ? lines[i - 1].text : " ")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                    Text(lines[i].text.isEmpty ? "♪" : lines[i].text)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(player.artColor)
                        .lineLimit(2)
                    Text(i + 1 < lines.count ? lines[i + 1].text : " ")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.55))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .task(id: player.current?.videoId) { await load() }
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
        let found = await Lyrics.search(title: track.title, artist: track.artist,
                                        videoId: track.videoId, duration: track.duration)
        await MainActor.run {
            lines = Lyrics.best(found)?.lines ?? []
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
