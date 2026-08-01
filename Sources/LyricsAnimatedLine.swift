import SwiftUI

/// One lyric line drawn in the chosen animation style, ported from the six
/// branches of `OriginalLyrics.kt`'s renderer. Every style needs per-word
/// stamps; a line without them (LrcLib, KuGou, plain YouTube) falls back to the
/// flat text, exactly as Android does when `hasWordTimings` is false.
///
/// Every style lays out through `WordFlow`, one view per syllable. Karaoke and
/// Apple used to mask a single `Text` with one horizontal gradient instead —
/// which looks right only while the line fits on one row. A line that WRAPS has
/// all of its rows inside that same left-to-right gradient, so they filled
/// together rather than the sweep travelling row by row: three rows lighting up
/// at once instead of word by word.
struct LyricsAnimatedLine: View {
    let line: LyricLine
    let position: Double
    let style: LyricsAnimation
    let isActive: Bool
    let size: Double
    let spacing: Double
    let alignment: TextAlignment
    let frameAlignment: Alignment
    let color: Color
    /// Romanisation or translation, drawn under the line. Nil when neither is on.
    var secondary: String?
    /// Romanization → "Use it as the main line": the romanisation takes the
    /// original's place instead of sitting under it.
    var secondaryAsMain = false

    private var font: Font { .system(size: size, weight: .bold) }
    private var leading: CGFloat { size * (spacing - 1) }
    private var displayText: String {
        if secondaryAsMain, let secondary, !secondary.isEmpty { return secondary }
        return line.text.isEmpty ? "♪" : line.text
    }

    /// Word effects only make sense on the line being sung right now.
    private var animating: Bool {
        // Word stamps line up with the original text, so a swapped-in
        // romanisation animates as a whole line rather than per word.
        isActive && line.hasWordTimings && style != .none && !secondaryAsMain
    }

    var body: some View {
        VStack(alignment: frameAlignment.horizontal, spacing: 4) {
            primary
            if let secondary, !secondary.isEmpty, !secondaryAsMain {
                Text(secondary)
                    .font(.system(size: size * 0.6, weight: .medium))
                    .multilineTextAlignment(alignment)
                    .foregroundStyle(color.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            }
        }
    }

    @ViewBuilder private var primary: some View {
        if !animating {
            plain
        } else {
            Group {
                switch style {
                case .karaoke: wipe(soft: false)
                case .apple: wipe(soft: true)
                case .fade, .glow, .slide: perWord
                case .none: plain
                }
            }
            .scaleEffect(bounce)
        }
    }

    /// Android's `bounceScale`: a single 3% swell over the first third of the
    /// line's fill, then flat. It's what gives the active line its little kick
    /// as it starts — subtle enough that it reads as life rather than movement.
    private var bounce: Double {
        let fill = line.progress(at: position)
        guard fill < 0.3 else { return 1 }
        return 1 + sin(fill * 3.33 * .pi) * 0.03
    }

    // MARK: Flat

    private var plain: some View {
        Text(displayText)
            .font(font)
            .tracking(-0.5)
            .lineSpacing(leading)
            .multilineTextAlignment(alignment)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    // MARK: Karaoke / Apple — a wipe across the whole line

    /// A dim line with each syllable brightened as it's sung. The sweep is per
    /// WORD rather than across the block, so it follows the words onto the next
    /// row instead of filling every row at once. Karaoke's edge is hard;
    /// Apple's is a soft gradient with a glow, which is what makes it read as
    /// Apple Music rather than a progress bar.
    private func wipe(soft: Bool) -> some View {
        WordFlow(spacing: 0, lineSpacing: leading, alignment: frameAlignment) {
            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                syllable(word.text + " ", progress: reveal(word), soft: soft)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    /// One word: a dim copy with a bright copy masked over it.
    private func syllable(_ text: String, progress: Double, soft: Bool) -> some View {
        Text(text)
            .font(font)
            .tracking(-0.5)
            .foregroundStyle(color.opacity(0.35))
            .overlay {
                GeometryReader { geo in
                    Text(text)
                        .font(font)
                        .tracking(-0.5)
                        .foregroundStyle(color)
                        .shadow(color: soft ? color.opacity(0.5) : .clear, radius: 10)
                        .frame(width: geo.size.width, height: geo.size.height,
                               alignment: .leading)
                        .mask(alignment: .leading) {
                            if soft {
                                // Wider than the old block gradient: spread over
                                // one word, a 6% edge is a hard line again.
                                LinearGradient(stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: max(progress - 0.25, 0)),
                                    .init(color: .clear, location: min(progress + 0.25, 1)),
                                    .init(color: .clear, location: 1),
                                ], startPoint: .leading, endPoint: .trailing)
                            } else {
                                Rectangle().frame(width: geo.size.width * progress)
                            }
                        }
                }
            }
            .animation(.linear(duration: 0.12), value: progress)
    }

    // MARK: Fade / Glow / Slide — a view per word

    private var perWord: some View {
        WordFlow(spacing: 0, lineSpacing: leading, alignment: frameAlignment) {
            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                let sung = reveal(word)
                Text(word.text + " ")
                    .font(font)
                    .tracking(-0.5)
                    .foregroundStyle(color.opacity(style == .fade ? 0.35 + 0.65 * sung : 1))
                    .opacity(style == .fade ? 1 : (0.4 + 0.6 * sung))
                    .shadow(color: style == .glow ? color.opacity(0.6 * sung) : .clear,
                            radius: 8 * sung)
                    .offset(y: style == .slide ? -3 * sung : 0)
                    .animation(.easeOut(duration: 0.18), value: sung)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    /// 0 before the syllable, 1 after it, ramped across its own span.
    private func reveal(_ word: LyricWord) -> Double {
        guard word.end > word.start else { return position >= word.start ? 1 : 0 }
        return min(max((position - word.start) / (word.end - word.start), 0), 1)
    }
}

/// A wrapping row of words. SwiftUI has no wrapping stack, and the per-word
/// styles need one view per syllable; greedy word breaking matches how `Text`
/// wraps the same string, so line heights stay in step with the pane's measure.
struct WordFlow: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 0
    var alignment: Alignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } +
            max(0, CGFloat(rows.count - 1)) * lineSpacing
        return CGSize(width: maxWidth == .infinity ? rows.map(\.width).max() ?? 0 : maxWidth,
                      height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            switch alignment.horizontal {
            case .trailing: x += bounds.width - row.width
            case .center: x += (bounds.width - row.width) / 2
            default: break
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.width == 0 ? size.width : row.width + spacing + size.width
            if next > maxWidth, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = next
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// The instrumental-break marker, ported from `IntervalIndicator` in
/// ExperimentalLyrics.kt: three dots that swell in while the break runs and fill
/// left-to-right as it elapses, then collapse as the next line arrives.
struct IntervalIndicator: View {
    let start: Double
    let end: Double
    let position: Double
    /// True while this break is the current item.
    let active: Bool
    let tint: Color

    /// Android stops the indicator 650ms before the next line, so it's gone by
    /// the time the singing starts.
    private var progress: Double {
        let span = end - 0.65 - start
        guard span > 0 else { return 0 }
        return min(max((position - start) / span, 0), 1)
    }

    /// Android runs the drift and the breathing off a 2.6s linear loop. Taking
    /// the phase from the playback position rather than a timer keeps this free
    /// of any clock of its own — nothing here can drift against the lyrics, and
    /// it settles when playback does.
    private var phase: Double {
        let loop = 2.6
        let t = position.truncatingRemainder(dividingBy: loop) / loop
        return t < 0 ? t + 1 : t
    }

    var body: some View {
        ZStack {
            floatingNotes
            // A slow swell on the loop, exactly Android's 1 + 0.06·|sin(πt)|.
            glyph(breathe: 1 + 0.06 * abs(sin(phase * .pi)))
        }
        .opacity(active ? 1 : 0.25)
        .animation(.easeInOut(duration: 0.35), value: active)
        // Centred regardless of the chosen text position, as Android's
        // wrapContentWidth(CenterHorizontally) puts it.
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: Self.height)
    }

    /// Must match `LyricsPane.gapHeight`, which is what the scroll maths measures
    /// a break as — if the two disagree the lines below drift out of place.
    static let height: CGFloat = 118

    /// A dim glyph with a brighter copy filling it from the bottom as the break
    /// runs down, tinted white→accent like Android's clef.
    private func glyph(breathe: Double) -> some View {
        let size: CGFloat = 54
        return ZStack {
            Image(systemName: "music.note")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint.opacity(0.26))
            Image(systemName: "music.note")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, tint.opacity(0.95)],
                                                startPoint: .top, endPoint: .bottom))
                .mask(alignment: .bottom) {
                    GeometryReader { g in
                        Rectangle()
                            .frame(height: g.size.height * progress)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
        }
        .scaleEffect(breathe)
        .animation(.linear(duration: 0.12), value: progress)
    }

    /// Six notes rising past the glyph on staggered phases, fading in and out so
    /// none of them is ever cut off. Positions and phases are Android's.
    private var floatingNotes: some View {
        ForEach(Self.notes, id: \.x) { note in
            let p = (phase + note.phase).truncatingRemainder(dividingBy: 1)
            let fade = sin(p * .pi) * sin(p * .pi) * 0.55
            Image(systemName: "music.note")
                .font(.system(size: note.size, weight: .medium))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(8 * sin((p + note.phase) * 2 * .pi)))
                .opacity(fade)
                .offset(x: note.x + note.drift * sin(p * 2 * .pi),
                        y: 30 - 84 * p)
        }
    }

    private struct Note {
        let x: CGFloat, size: CGFloat, phase: Double, drift: CGFloat
    }

    private static let notes: [Note] = [
        Note(x: -78, size: 13, phase: 0.00, drift: -7),
        Note(x: -50, size: 10, phase: 0.42, drift: 6),
        Note(x: 52, size: 12, phase: 0.68, drift: 7),
        Note(x: 82, size: 14, phase: 0.20, drift: -6),
        Note(x: -26, size: 9, phase: 0.85, drift: 5),
        Note(x: 30, size: 9, phase: 0.55, drift: -5),
    ]
}
