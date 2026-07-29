import SwiftUI
import UIKit

/// Inline lyrics, ported from ExperimentalLyrics.kt.
///
/// Lines are absolutely positioned from their measured heights against a 35%
/// anchor — not a scroll view — and the playback position is re-derived every
/// frame by extrapolating wall-clock time from the last player sample, so the
/// highlight glides instead of stepping with the 4 Hz position updates.
struct LyricsPane: View {
    @ObservedObject var player: Player
    @ObservedObject private var look = LookFeel.shared
    /// The 4 Hz position drives the sync anchor, so observe it directly rather
    /// than trusting the parent to re-render us.
    @ObservedObject private var clock: PlaybackClock

    init(player: Player) {
        self.player = player
        _clock = ObservedObject(wrappedValue: player.clock)
    }

    @State private var candidates: [LyricsCandidate] = []
    @State private var result: LyricsResult?
    @State private var loading = true
    @State private var showVersions = false
    @State private var provider = Lyrics.sourceName

    // Position smoothing anchors (see the withFrameNanos loop in Kotlin).
    @State private var anchorPos: Double = 0
    @State private var anchorWall = Date()

    // Scroll engine.
    @State private var manualOffset: CGFloat = 0
    @State private var dragStart: CGFloat = 0
    @State private var autoScroll = true
    @State private var ready = false

    private let anchorRatio: CGFloat = 0.35
    private let fallbackHeight: CGFloat = 68
    private let itemGap: CGFloat = 16
    private let fadeTop: CGFloat = 130
    private let fadeBottom: CGFloat = 160

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .task(id: player.current?.videoId) { await load() }
        .onChange(of: clock.currentTime) {
            // Re-anchor whenever the player reports a new position.
            anchorPos = player.currentTime
            anchorWall = Date()
        }
        .sheet(isPresented: $showVersions) {
            LyricsVersionPicker(candidates: candidates, current: result) { pick in
                result = pick.result
                provider = pick.provider
                if let id = player.current?.videoId { LyricsStore.save(pick, for: id) }
                showVersions = false
            }
        }
    }

    /// The genuine track length. `Track.duration` is 0 for songs parsed out of
    /// YouTube, so prefer what the player measured off the stream — the lyric
    /// providers use it to tell versions of a song apart.
    private var knownDuration: Double {
        player.duration > 0 ? player.duration : (player.current?.duration ?? 0)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Spacer()
            if !autoScroll {
                Button { resync() } label: {
                    Text("Auto scroll")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white)
                        .clipShape(Capsule())
                }
            }
            Button { showVersions = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "character.bubble")
                    Text("Language")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            }
            .disabled(candidates.count < 2)
            .opacity(candidates.count < 2 ? 0.4 : 1)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if loading {
            VStack(spacing: 22) {
                SkeletonBox(width: 220, height: 26)
                SkeletonBox(width: 280, height: 26)
                SkeletonBox(width: 190, height: 26)
                SkeletonBox(width: 250, height: 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let r = result, r.synced, !r.lines.isEmpty {
            syncedStage(r.lines)
        } else if let plain = result?.plain, !plain.isEmpty {
            ScrollView(showsIndicators: false) {
                Text(plain)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                    .lineSpacing(6)
                    .multilineTextAlignment(look.lyricsPosition.textAlignment)
                    .frame(maxWidth: .infinity, alignment: look.lyricsPosition.frameAlignment)
                    .padding(.horizontal, 24).padding(.vertical, 24)
            }
        } else {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "music.note.list").font(.system(size: 34)).opacity(0.5)
                Text("Lyrics not found").foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
    }

    // MARK: The absolutely-positioned lyric stage

    private func syncedStage(_ lines: [LyricLine]) -> some View {
        GeometryReader { geo in
            let anchorY = geo.size.height * anchorRatio
            let textWidth = geo.size.width - 48
            // Heights are measured deterministically from the text metrics, so the
            // stack positions correctly on the very first frame (no measure pass).
            let hs = lines.map { lineHeight($0.text, width: textWidth) }

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !player.isPlaying)) { timeline in
                let pos = smoothedPosition(at: timeline.date)
                let highlight = index(in: lines, at: pos)             // no lead
                let scrollTo = max(index(in: lines, at: pos + 0.25), 0) // +250ms scroll lead
                let map = positions(active: scrollTo, heights: hs)

                ZStack(alignment: .top) {
                    // "Lyrics from …" floats just above line 0 and scrolls with it.
                    if result != nil {
                        Text("Lyrics from \(provider)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .offset(y: anchorY + (map[0] ?? 0) - 34 + manualOffset)
                            .animation(lineAnimation(distance: scrollTo), value: map[0])
                    }

                    ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                        let target = anchorY + (map[i] ?? 0) + manualOffset
                        let distance = abs(i - scrollTo)

                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: 30, weight: .bold))
                            .tracking(-0.5)
                            .lineSpacing(4)
                            .multilineTextAlignment(look.lyricsPosition.textAlignment)
                            .foregroundStyle(.white.opacity(alpha(distance: distance, isActive: i == highlight)))
                            .frame(maxWidth: .infinity, alignment: look.lyricsPosition.frameAlignment)
                            .padding(.vertical, 12)
                            .offset(y: target)
                            .animation(lineAnimation(distance: distance), value: target)
                            .animation(.easeInOut(duration: 0.25), value: highlight)
                            .contentShape(Rectangle())
                            .onTapGesture { seek(to: line) }
                    }
                }
                // Must fill the stage: offsets don't affect layout, so without an
                // explicit height the stack collapses to one line and the mask
                // clips every other line away.
                .frame(width: geo.size.width - 48, height: geo.size.height, alignment: .top)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .mask(fadeMask(height: geo.size.height))
            .contentShape(Rectangle())
            .gesture(manualScroll)
        }
    }

    /// Wrapped height of a line plus its 12pt vertical padding.
    private func lineHeight(_ text: String, width: CGFloat) -> CGFloat {
        guard width > 0 else { return fallbackHeight }
        let body = text.isEmpty ? "♪" : text
        let font = UIFont.systemFont(ofSize: 30, weight: .bold)
        let rect = (body as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font], context: nil)
        return ceil(rect.height) + 24
    }

    /// Linear alpha ramp over the top 130pt and the bottom 160pt.
    private func fadeMask(height: CGFloat) -> some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: min(fadeTop / max(height, 1), 0.45)),
            .init(color: .black, location: max(1 - fadeBottom / max(height, 1), 0.55)),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Engine

    /// Extrapolate from the last player sample using wall clock, only while playing.
    private func smoothedPosition(at date: Date) -> Double {
        player.isPlaying ? anchorPos + date.timeIntervalSince(anchorWall) : anchorPos
    }

    /// Last line whose start has passed (a line runs until the next one starts).
    private func index(in lines: [LyricLine], at pos: Double) -> Int {
        var idx = -1
        for (i, line) in lines.enumerated() {
            if line.time <= pos { idx = i } else { break }
        }
        return idx
    }

    /// Offsets relative to the active line, summed from the measured heights.
    private func positions(active: Int, heights: [CGFloat]) -> [Int: CGFloat] {
        let count = heights.count
        guard count > 0, active >= 0, active < count else { return [:] }
        var map: [Int: CGFloat] = [active: 0]
        var y: CGFloat = 0
        var i = active - 1
        while i >= 0 {
            y -= (heights[i] + itemGap)
            map[i] = y
            i -= 1
        }
        y = 0
        i = active
        while i < count - 1 {
            y += (heights[i] + itemGap)
            map[i + 1] = y
            i += 1
        }
        return map
    }

    /// tween(750ms, delay = min(distance × 20, 200)ms, FastOutSlowInEasing)
    private func lineAnimation(distance: Int) -> Animation? {
        guard autoScroll, ready else { return nil }   // snap on first layout / manual scroll
        let delay = min(Double(distance) * 0.02, 0.2)
        return .timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.75).delay(delay)
    }

    private func alpha(distance: Int, isActive: Bool) -> Double {
        if isActive { return 1.0 }
        guard autoScroll else { return 0.2 }
        switch distance {
        case 0: return 0.3
        case 1, 2: return 0.2
        case 3: return 0.15
        case 4: return 0.1
        default: return 0.08
        }
    }

    // MARK: Interaction

    private var manualScroll: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                if autoScroll {
                    autoScroll = false
                    dragStart = manualOffset
                }
                manualOffset = dragStart + v.translation.height
            }
    }

    private func seek(to line: LyricLine) {
        guard player.duration > 0 else { return }
        player.seek(to: line.time / player.duration)
        resync()
    }

    /// Glide the manual offset home: |offset|/4 ms, clamped to 200…600.
    private func resync() {
        let duration = min(max(Double(abs(manualOffset)) / 4 / 1000, 0.2), 0.6)
        autoScroll = true
        withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: duration)) { manualOffset = 0 }
    }

    private func load() async {
        loading = true
        result = nil
        candidates = []
        manualOffset = 0
        autoScroll = true
        ready = false
        guard let track = player.current else { loading = false; return }

        // A downloaded song carries its lyrics on disk — use them offline.
        if let cached = Downloads.shared.cachedLyrics(for: track.videoId) {
            result = cached
            loading = false
            ready = true
            return
        }

        // Whatever source you last chose for this song wins.
        if let saved = LyricsStore.load(for: track.videoId) {
            provider = saved.provider
            result = saved.result
            loading = false
            ready = true
            // Still offer the alternatives; the player has usually warmed these
            // already, so the picker fills in without another five-provider search.
            let found = await LyricsCache.shared.warm(videoId: track.videoId, title: track.title,
                                                      artist: track.artist, duration: knownDuration)
            await MainActor.run { candidates = found }
            return
        }

        // Warmed in the background when the song started, so this is usually a
        // cache hit and the pane opens already populated.
        let found = await LyricsCache.shared.warm(videoId: track.videoId, title: track.title,
                                                  artist: track.artist, duration: knownDuration)
        await MainActor.run {
            candidates = found
            result = Lyrics.best(found)
            provider = found.first(where: { $0.result == Lyrics.best(found) })?.provider ?? Lyrics.sourceName
            loading = false
        }
        // Let the first frame land at its position, then start animating.
        try? await Task.sleep(nanoseconds: 120_000_000)
        await MainActor.run { ready = true }
    }
}

/// Version/source picker opened by the Language button.
struct LyricsVersionPicker: View {
    let candidates: [LyricsCandidate]
    let current: LyricsResult?
    let onPick: (LyricsCandidate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates) { c in
                    Button { onPick(c) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(c.preview.isEmpty ? c.trackName : c.preview)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            HStack(spacing: 6) {
                                Text(c.provider)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Blaze.amber)
                                if let script = c.script {
                                    Text(script)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color.white.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                if c.synced {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                                }
                                Spacer(minLength: 0)
                                if c.result == current {
                                    Image(systemName: "checkmark").foregroundStyle(Blaze.amber)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.white.opacity(0.05))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Blaze.scaffold.ignoresSafeArea())
            .navigationTitle("Choose lyrics source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Blaze.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
