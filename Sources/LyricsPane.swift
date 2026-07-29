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
    @ObservedObject private var prefs = LyricsPrefs.shared
    @ObservedObject private var extraLines = LyricsSecondary.shared
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
                prepareSecondary(result)
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

    /// Kick off the second line for these lyrics. Cached per song inside
    /// `LyricsSecondary`, so this is safe to call whenever a result arrives and
    /// never fires a paid translation twice for the same track.
    private func prepareSecondary(_ result: LyricsResult?) {
        guard let result, !result.lines.isEmpty,
              let id = player.current?.videoId else { return }
        LyricsSecondary.shared.prepare(videoId: id, lyrics: result.lines)
    }

    private func syncedStage(_ lines: [LyricLine]) -> some View {
        GeometryReader { geo in
            let anchorY = geo.size.height * anchorRatio
            let textWidth = geo.size.width - 48
            // Lines, plus the instrumental gaps between them when the Blazify
            // style is on. Heights are measured deterministically from the text
            // metrics, so the stack positions correctly on the very first frame.
            let items = stageItems(lines)
            let secondary = secondaryAgent(lines)
            let hs = items.map { item -> CGFloat in
                switch item {
                case .line(let i, let line):
                    // As-main replaces the text rather than adding a row, so it
                    // must not also add the second line's height.
                    let extra = RomanizePrefs.shared.asMain ? nil : secondaryText(i)
                    return lineHeight(line.text, width: textWidth, secondary: extra)
                case .gap: return Self.gapHeight
                }
            }

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !player.isPlaying)) { timeline in
                let pos = smoothedPosition(at: timeline.date)
                let highlight = itemIndex(in: items, at: pos)          // no lead
                let scrollTo = prefs.autoScroll
                    ? max(itemIndex(in: items, at: pos + 0.25), 0)     // +250ms scroll lead
                    : 0
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

                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        let target = anchorY + (map[i] ?? 0) + manualOffset
                        let distance = abs(i - scrollTo)
                        let active = i == highlight

                        Group {
                            switch item {
                            case .gap(let start, let end):
                                IntervalIndicator(start: start, end: end, position: pos,
                                                  active: active, tint: .white)
                            case .line(_, let line):
                                let side = alignment(for: line, secondary: secondary)
                                // Android stores line spacing as a multiplier of
                                // the type size; the line view converts it to leading.
                                LyricsAnimatedLine(
                                    line: line, position: pos, style: effectiveAnimation,
                                    isActive: active, size: effectiveSize,
                                    spacing: effectiveSpacing,
                                    alignment: side.textAlignment,
                                    frameAlignment: side.frameAlignment,
                                    color: .white.opacity(alpha(distance: distance, isActive: active)),
                                    secondary: secondaryText(itemLineIndex(item)),
                                    secondaryAsMain: RomanizePrefs.shared.enabled
                                        && RomanizePrefs.shared.asMain)
                                    .shadow(color: effectiveGlow && active
                                            ? .white.opacity(0.45) : .clear,
                                            radius: 12)
                                    .scaleEffect(effectiveGlow && active ? 1.03 : 1,
                                                 anchor: look.lyricsPosition.scaleAnchor)
                            }
                        }
                            .frame(maxWidth: .infinity, alignment: look.lyricsPosition.frameAlignment)
                            .padding(.vertical, 12)
                            .offset(y: target)
                            .animation(lineAnimation(distance: distance), value: target)
                            .animation(.easeInOut(duration: 0.25), value: highlight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if prefs.clickToSeek, case .line(_, let line) = item { seek(to: line) }
                            }
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

    // MARK: Blazify style

    /// The Blazify renderer sets its own type and always highlights word by
    /// word — which is why Settings hides size, spacing, glow and animation
    /// while it's on, exactly as Android hides them behind experimental lyrics.
    private var effectiveSize: Double { prefs.blazifyStyle ? 34 : prefs.textSize }
    private var effectiveSpacing: Double { prefs.blazifyStyle ? 1.3 : prefs.lineSpacing }
    private var effectiveAnimation: LyricsAnimation { prefs.blazifyStyle ? .apple : prefs.animation }
    private var effectiveGlow: Bool { prefs.blazifyStyle ? true : prefs.glowEffect }

    /// A duet's second voice, if the lyrics name more than one agent. Only
    /// meaningful when the provider gives TTML — LRC has no such notion.
    private func secondaryAgent(_ lines: [LyricLine]) -> String? {
        guard prefs.respectAgentPositioning else { return nil }
        var seen: [String] = []
        for line in lines {
            guard let agent = line.agent, !seen.contains(agent) else { continue }
            seen.append(agent)
            if seen.count > 1 { break }
        }
        return seen.count > 1 ? seen[1] : nil
    }

    /// Where a line sits. Background/second-voice lines mirror to the opposite
    /// side, which is what Android's respect-agent-positioning does; everything
    /// else follows the chosen text position.
    private func alignment(for line: LyricLine, secondary: String?) -> LyricsPosition {
        guard let secondary, line.agent == secondary else { return look.lyricsPosition }
        switch look.lyricsPosition {
        case .left: return .right
        case .right: return .left
        case .center: return .right
        }
    }

    /// Instrumental breaks shorter than this aren't worth marking.
    private static let minGap: Double = 5
    private static let gapHeight: CGFloat = 46

    /// A line, or the instrumental gap before one.
    enum StageItem: Identifiable {
        case line(Int, LyricLine)
        case gap(Double, Double)

        var id: String {
            switch self {
            case .line(let i, _): return "line-\(i)"
            case .gap(let start, let end): return "gap-\(start)-\(end)"
            }
        }
    }

    /// The display list. Only the Blazify style inserts gap markers; the classic
    /// renderer gets the lines untouched, so its layout is unchanged.
    private func stageItems(_ lines: [LyricLine]) -> [StageItem] {
        guard prefs.blazifyStyle else {
            return lines.enumerated().map { .line($0.offset, $0.element) }
        }
        var out: [StageItem] = []
        var previousEnd: Double = 0
        for (i, line) in lines.enumerated() {
            // A line ends at its last syllable when we have word stamps, and at
            // the next line's start when we don't.
            if line.time - previousEnd >= Self.minGap {
                out.append(.gap(previousEnd, line.time))
            }
            out.append(.line(i, line))
            previousEnd = line.words.last?.end
                ?? (i + 1 < lines.count ? min(lines[i + 1].time, line.time + 6) : line.time)
        }
        return out
    }

    /// Last item whose window has started — a gap counts as current until the
    /// line after it begins.
    private func itemIndex(in items: [StageItem], at pos: Double) -> Int {
        var idx = -1
        for (i, item) in items.enumerated() {
            let start: Double
            switch item {
            case .line(_, let line): start = line.time
            case .gap(let gapStart, _): start = gapStart
            }
            if start <= pos { idx = i } else { break }
        }
        return idx
    }

    /// The romanisation or translation for a line, if one has been prepared.
    private func secondaryText(_ lineIndex: Int?) -> String? {
        guard let lineIndex, let id = player.current?.videoId else { return nil }
        return extraLines.text(for: id, line: lineIndex)
    }

    private func itemLineIndex(_ item: StageItem) -> Int? {
        if case .line(let i, _) = item { return i }
        return nil
    }

    /// Wrapped height of a line plus its 12pt vertical padding, measured with
    /// the very type it's drawn with — size and spacing both come from Settings,
    /// so a stale constant here would misplace every line.
    private func lineHeight(_ text: String, width: CGFloat,
                            secondary: String? = nil) -> CGFloat {
        guard width > 0 else { return fallbackHeight }
        let body = text.isEmpty ? "♪" : text
        let leading = effectiveSize * (effectiveSpacing - 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = leading

        func measure(_ string: String, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
            let font = UIFont.systemFont(ofSize: size, weight: weight)
            return (string as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: paragraph], context: nil).height
        }

        var height = measure(body, size: effectiveSize, weight: .bold)
        // The romanisation / translation sits under the line at 0.6× with a 4pt
        // gap — the same numbers the line view draws it with, so the measured
        // height and the drawn height can't drift apart.
        if let secondary, !secondary.isEmpty {
            height += 4 + measure(secondary, size: effectiveSize * 0.6, weight: .medium)
        }
        return ceil(height) + 24
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
        guard autoScroll, prefs.autoScroll, ready else { return nil }   // snap on first layout / manual scroll
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
        // Cached songs keep lyrics beside the audio too, so offline playback of
        // anything you've heard before still shows words.
        if let cached = Downloads.shared.cachedLyrics(for: track.videoId)
            ?? AudioCache.shared.cachedLyrics(for: track.videoId) {
            result = cached
            prepareSecondary(result)
            loading = false
            ready = true
            return
        }

        // Whatever source you last chose for this song wins.
        if let saved = LyricsStore.load(for: track.videoId) {
            provider = saved.provider
            result = saved.result
            prepareSecondary(result)
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
            prepareSecondary(result)
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
