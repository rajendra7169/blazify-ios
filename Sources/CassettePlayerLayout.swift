import SwiftUI

/// CASSETTE design. It replaces the
/// standard chrome entirely: the cream waveform card is the only seek surface (and
/// owns the heart), shuffle/repeat live in the retro transport row, and lyrics /
/// queue / sleep / palette / more live in the bottom pill.
struct CassettePlayerLayout: View {
    @ObservedObject var player: Player
    var onLyrics: () -> Void
    var onQueue: () -> Void
    var onSleep: () -> Void
    var onTheme: () -> Void
    var onMore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header — plain (not bold, no shadow), unlike FULL_ART.
            VStack(spacing: 4) {
                Text("Now Playing").font(.system(size: 16, weight: .medium))
                if let from = player.current?.artist, !from.isEmpty {
                    Text(from)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 48)

            // Tape stage.
            CassetteTapeView(
                isPlaying: player.isPlaying,
                progress: player.progress,
                accent: player.artColor,
                artURL: player.current?.artURL(size: 720),
            )
            .padding(.horizontal, 32)
            .frame(maxHeight: .infinity)

            // Title / artist.
            VStack(spacing: 2) {
                Text(player.current?.title ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                Text(player.current?.artist ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 12)
            RetroWaveformCard(player: player).padding(.horizontal, 32)
            Spacer().frame(height: 14)
            RetroTransportRow(player: player).padding(.horizontal, 32)
            Spacer().frame(height: 14)
            RetroBottomRow(accent: player.artColor, sleepActive: player.sleepActive,
                           onLyrics: onLyrics, onQueue: onQueue, onSleep: onSleep,
                           onTheme: onTheme, onMore: onMore)
                .padding(.horizontal, 32)
            Spacer().frame(height: 16)
        }
        .foregroundStyle(.white)
    }
}

/// Cream card holding the times, the 36-bar waveform (tap AND drag to seek), and
/// the favourite heart.
struct RetroWaveformCard: View {
    @ObservedObject var player: Player

    private let barCount = 36

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 4) {
                HStack {
                    Text(timeString(player.currentTime))
                    Spacer()
                    Text(player.duration > 0 ? timeString(player.duration) : "")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Retro.ink)

                GeometryReader { geo in
                    Canvas { ctx, size in
                        let frac = player.progress
                        let gap = size.width / CGFloat(barCount)
                        let barW = gap * 0.55
                        for i in 0..<barCount {
                            let wave = abs(sin(Double(i) * 1.7) * 0.5 + sin(Double(i) * 0.53 + 1.3) * 0.5)
                            let barH = size.height * min(max(0.30 + 0.65 * CGFloat(wave), 0.15), 1)
                            let x = gap * CGFloat(i) + (gap - barW) / 2
                            let played = (Double(i) + 0.5) / Double(barCount) <= frac
                            ctx.fill(
                                Path(roundedRect: CGRect(x: x, y: (size.height - barH) / 2,
                                                         width: barW, height: barH),
                                     cornerRadius: barW / 2),
                                with: .color(played ? player.artColor : Retro.ink.opacity(0.25)))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in seek(g.location.x, geo.size.width) }
                            .onEnded { g in seek(g.location.x, geo.size.width) },
                    )
                }
                .frame(height: 40)
            }

            Button { player.toggleFavorite() } label: {
                Image(systemName: player.isCurrentFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundStyle(player.isCurrentFavorite ? .red : Retro.ink)
                    .frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Retro.cream)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    private func seek(_ x: CGFloat, _ width: CGFloat) {
        guard width > 0 else { return }
        player.seek(to: min(max(Double(x / width), 0), 1))
    }
}

/// Chunky retro keys: shuffle · [prev] · [PLAY] · [next] · repeat.
struct RetroTransportRow: View {
    @ObservedObject var player: Player

    var body: some View {
        HStack(spacing: 0) {
            flatIcon("shuffle", active: player.isShuffled) { player.toggleShuffle() }
            Spacer().frame(width: 8)
            RetroKey(width: 62, height: 50, bg: Retro.cream) { player.prev() } content: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 22)).foregroundStyle(Retro.ink)
            }
            Spacer().frame(width: 12)
            RetroKey(width: 76, height: 56, bg: player.artColor) { player.toggle() } content: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26)).foregroundStyle(.white)
            }
            Spacer().frame(width: 12)
            RetroKey(width: 62, height: 50, bg: Retro.cream) { player.next() } content: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 22)).foregroundStyle(Retro.ink)
            }
            Spacer().frame(width: 8)
            flatIcon(player.repeatMode == .one ? "repeat.1" : "repeat",
                     active: player.repeatMode != .off) { player.cycleRepeat() }
        }
        .frame(maxWidth: .infinity)
    }

    private func flatIcon(_ name: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 20))
                .foregroundStyle(active ? player.artColor : .white)
                .frame(width: 40, height: 40)
        }
    }
}

/// A single chunky key: 16pt radius, drop shadow + a white hairline top border.
struct RetroKey<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let bg: Color
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: width, height: height)
                .background(bg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.25), lineWidth: 1),
                )
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

/// One pill of five butted segments; the lyrics segment is permanently accent-filled.
struct RetroBottomRow: View {
    let accent: Color
    let sleepActive: Bool
    var onLyrics: () -> Void
    var onQueue: () -> Void
    var onSleep: () -> Void
    var onTheme: () -> Void
    var onMore: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment("text.alignleft", bg: accent, tint: .white, action: onLyrics)
            segment("list.bullet", bg: Retro.darkKey, tint: Retro.cream, action: onQueue)
            segment(sleepActive ? "moon.zzz.fill" : "moon.zzz",
                    bg: Retro.darkKey, tint: sleepActive ? accent : Retro.cream, action: onSleep)
            segment("paintpalette", bg: Retro.darkKey, tint: Retro.cream, action: onTheme)
            segment("ellipsis", bg: Retro.darkKey, tint: Retro.cream, action: onMore)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
    }

    private func segment(_ icon: String, bg: Color, tint: Color,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(bg)
        }
        .buttonStyle(.plain)
    }
}
