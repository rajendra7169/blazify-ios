import SwiftUI
import UIKit

/// CASSETTE design. It replaces the
/// standard chrome entirely: the cream waveform card is the only seek surface (and
/// owns the heart), shuffle/repeat live in the retro transport row, and lyrics /
/// queue / sleep / palette / more live in the bottom pill.
struct CassettePlayerLayout: View {
    @ObservedObject var player: Player
    /// Watched here as well as in the waveform card: the reels are handed a
    /// progress figure as a plain value, and a value is only as fresh as the
    /// view that passed it. Taken as a parameter rather than reached for
    /// through the player, so this keeps its memberwise initialiser — which
    /// means it must be declared where it is passed, since a memberwise
    /// initialiser takes its arguments in the order the properties are written.
    @ObservedObject var clock: PlaybackClock
    var onLyrics: () -> Void
    var onQueue: () -> Void
    var onSleep: () -> Void
    var onTheme: () -> Void
    var onMore: () -> Void

    private var played: Double {
        player.duration > 0 ? min(max(clock.currentTime / player.duration, 0), 1) : 0
    }

    private var sleepLabel: String {
        if player.sleepAtEndOfSong { return "End of song" }
        if let r = player.sleepRemaining { return timeString(r) }
        return "Sleep timer"
    }

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
                progress: played,
                accent: player.artColor,
                artURL: player.current?.artURL(size: 720),
            )
            .padding(.horizontal, 32)
            .frame(maxHeight: .infinity)

            // Title on the left with its own keys beside it, the way every
            // other design now reads. The heart came up here from the waveform
            // card, where it was the only design keeping it.
            CassetteTitleKeys(player: player, onTheme: onTheme, onMore: onMore)
                .padding(.horizontal, 32)

            Spacer().frame(height: 14)
            RetroWaveformCard(player: player).padding(.horizontal, 32)
            Spacer().frame(height: 20)
            RetroTransportRow(player: player).padding(.horizontal, 32)
            // The keys and the row underneath were almost touching.
            Spacer().frame(height: 26)
            RetroBottomRow(accent: player.artColor, sleepActive: player.sleepActive,
                           sleepLabel: sleepLabel,
                           onLyrics: onLyrics, onQueue: onQueue, onSleep: onSleep)
                .padding(.horizontal, 32)
            Spacer().frame(height: 20)
        }
        .foregroundStyle(.white)
    }
}

/// The song's name on the left, with its own raised keys beside it: keep, theme,
/// and the rest of the menu — the same three the other designs put by the title.
struct CassetteTitleKeys: View {
    @ObservedObject var player: Player
    var onTheme: () -> Void
    var onMore: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                Text(player.current?.artist ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .opensArtist(player)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            key(player.isCurrentFavorite ? "heart.fill" : "heart",
                tint: player.isCurrentFavorite ? .red : Retro.ink) { player.toggleFavorite() }
            key("paintpalette", action: onTheme)
            key("ellipsis", action: onMore)
        }
    }

    private func key(_ icon: String, tint: Color = Retro.ink,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(tint)
                .frame(width: 38, height: 34)
                .background(Retro.cream)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// Cream card holding the times and the 36-bar waveform (tap AND drag to seek).
struct RetroWaveformCard: View {
    @ObservedObject var player: Player
    /// The live position is published by its own observable, not by the player —
    /// deliberately, so that four updates a second do not re-render every screen
    /// in the app. The cost is that reading `player.currentTime` subscribes a
    /// view to nothing at all: this card drew itself once, with a position of
    /// zero and a duration not yet known, and then never again. Watching the
    /// clock is what every other view that draws time already does.
    @ObservedObject private var clock: PlaybackClock

    init(player: Player) {
        self.player = player
        _clock = ObservedObject(wrappedValue: player.clock)
    }

    private let barCount = 36

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                if player.isCurrentLive {
                    // Even in cream and plastic, a station is on air, not at a time.
                    LiveBadge(color: Retro.ink)
                    Spacer()
                } else {
                    Text(timeString(clock.currentTime))
                    Spacer()
                    Text(player.duration > 0 ? timeString(player.duration) : "")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Retro.ink)

            GeometryReader { geo in
                Canvas { ctx, size in
                    let frac = player.duration > 0
                        ? min(max(clock.currentTime / player.duration, 0), 1)
                        : 0
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
    /// What the sleep key says: the time left, "End of song", or its name.
    let sleepLabel: String
    var onLyrics: () -> Void
    var onQueue: () -> Void
    var onSleep: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment("list.bullet", "Queue", action: onQueue)
            VStack(spacing: 3) {
                RoutePicker(tint: UIColor(Retro.ink), activeTint: UIColor(accent))
                    .frame(width: 22, height: 22)
                Text("AirPlay").font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(Retro.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Retro.cream)
            .accessibilityLabel("AirPlay and Bluetooth")
            segment(sleepActive ? "moon.zzz.fill" : "moon.zzz", sleepLabel,
                    tint: sleepActive ? accent : Retro.ink, action: onSleep)
            segment("text.alignleft", "Lyrics", tint: accent, action: onLyrics)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
    }

    private func segment(_ icon: String, _ label: String, tint: Color = Retro.ink,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18))
                Text(label).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Retro.cream)
        }
        .buttonStyle(.plain)
    }
}
