import SwiftUI

/// One lyric line drawn in the chosen animation style, ported from the six
/// branches of `OriginalLyrics.kt`'s renderer. Every style needs per-word
/// stamps; a line without them (LrcLib, KuGou, plain YouTube) falls back to the
/// flat text, exactly as Android does when `hasWordTimings` is false.
///
/// Karaoke and Apple wipe a mask across a single `Text`, so their metrics match
/// the pane's height measurement exactly. Fade, Glow and Slide need a view per
/// word, and lay out through `WordFlow`.
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

    private var font: Font { .system(size: size, weight: .bold) }
    private var leading: CGFloat { size * (spacing - 1) }
    private var displayText: String { line.text.isEmpty ? "♪" : line.text }

    /// Word effects only make sense on the line being sung right now.
    private var animating: Bool { isActive && line.hasWordTimings && style != .none }

    var body: some View {
        if !animating {
            plain
        } else {
            switch style {
            case .karaoke: wipe(soft: false)
            case .apple: wipe(soft: true)
            case .fade, .glow, .slide: perWord
            case .none: plain
            }
        }
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

    /// A dim copy with a bright copy over it, revealed left-to-right as the line
    /// is sung. Karaoke's edge is hard; Apple's is a soft gradient with a glow,
    /// which is what makes it read as Apple Music rather than a progress bar.
    private func wipe(soft: Bool) -> some View {
        let progress = line.progress(at: position)
        return plain
            .foregroundStyle(color.opacity(0.35))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Text(displayText)
                        .font(font)
                        .tracking(-0.5)
                        .lineSpacing(leading)
                        .multilineTextAlignment(alignment)
                        .foregroundStyle(color)
                        .shadow(color: soft ? color.opacity(0.5) : .clear, radius: 10)
                        .frame(width: geo.size.width, alignment: frameAlignment)
                        .mask(alignment: .leading) {
                            if soft {
                                LinearGradient(stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: max(progress - 0.06, 0)),
                                    .init(color: .clear, location: min(progress + 0.06, 1)),
                                    .init(color: .clear, location: 1),
                                ], startPoint: .leading, endPoint: .trailing)
                            } else {
                                Rectangle().frame(width: geo.size.width * progress)
                            }
                        }
                }
            }
            .animation(.linear(duration: 0.1), value: progress)
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

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                // Each dot lights as its third of the break goes by, and gives a
                // small pulse on the way.
                let share = min(max(progress * 3 - Double(i), 0), 1)
                Circle()
                    .fill(tint.opacity(0.25 + 0.75 * share))
                    .frame(width: 10, height: 10)
                    .scaleEffect(active ? 1 + 0.35 * sin(share * .pi) : 0.6)
            }
        }
        .opacity(active ? 1 : 0.25)
        .animation(.easeInOut(duration: 0.35), value: active)
        .animation(.linear(duration: 0.12), value: progress)
        .frame(height: 22)
    }
}
