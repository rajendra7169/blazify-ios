import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let track: SharedTrack?
    let art: Image?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), track: sample, art: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        // The gallery preview has to show the design, not an empty turntable.
        let track = context.isPreview ? sample : NowPlayingShare.read()
        completion(NowPlayingEntry(date: Date(), track: track, art: image()))
    }

    /// One reload, many entries. The playhead moves on its own, so rather than
    /// waking this extension every few seconds — a budget it would exhaust by
    /// mid-morning — we hand the system half an hour of pre-rendered clock and
    /// let the app push a fresh timeline the moment the song actually changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let track = NowPlayingShare.read()
        let art = image()
        let now = Date()

        guard let track, track.isPlaying else {
            completion(Timeline(entries: [NowPlayingEntry(date: now, track: track, art: art)],
                                policy: .never))
            return
        }

        let step: TimeInterval = 30
        let remaining = max(track.duration - track.position, 0)
        let span = min(max(remaining, step), 30 * 60)
        let entries = stride(from: 0, through: span, by: step).map {
            NowPlayingEntry(date: now.addingTimeInterval($0), track: track, art: art)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func image() -> Image? {
        NowPlayingShare.artwork().map { Image(uiImage: $0) }
    }

    private var sample: SharedTrack {
        SharedTrack(title: "Mix Music Disk", artist: "first club", videoId: "",
                    isPlaying: false, duration: 177, position: 0, stamp: Date())
    }
}

// MARK: - The turntable

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    var entry: NowPlayingEntry

    private var dark: Bool { scheme == .dark }
    private var track: SharedTrack? { entry.track }
    private var elapsed: Double { track?.position(at: entry.date) ?? 0 }
    private var fraction: Double {
        guard let track, track.duration > 0 else { return 0 }
        return elapsed / track.duration
    }
    /// A per-song tilt, so the label doesn't sit pinned at twelve o'clock
    /// through an entire album. Widgets can't animate a spin; this at least
    /// means two songs in a row don't look like the same frozen screenshot.
    private var tilt: Double {
        guard let id = track?.videoId, !id.isEmpty else { return 0 }
        return Double(abs(id.hashValue) % 360)
    }

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemLarge: large
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: medium
        }
    }

    // MARK: Home Screen

    private var small: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                VinylRecord(artwork: entry.art, diameter: g.size.width * 0.70, angle: tilt)
                Spacer(minLength: 6)
                Text(track?.title ?? "Blazify")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(Vinyl.ink(dark))
                    .lineLimit(1)
                Text(track?.artist.isEmpty == false ? track!.artist : "Tap to play")
                    .font(.system(size: 11.5, weight: .semibold, design: .serif))
                    .foregroundStyle(Vinyl.muted(dark))
                    .lineLimit(1)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
        }
        .padding(12)
        .containerBackground(for: .widget) { Vinyl.paper(dark) }
        .widgetURL(BlazifyLink.player)
    }

    /// The reference layout: record on the left sized to the full height, then a
    /// column of title, bar, times and transport on the right.
    private var medium: some View {
        GeometryReader { g in
            HStack(spacing: 14) {
                VinylRecord(artwork: entry.art, diameter: g.size.height * 0.94, angle: tilt)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track?.title ?? "Nothing playing")
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundStyle(Vinyl.ink(dark))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(track?.artist.isEmpty == false ? track!.artist : "Blazify")
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(Vinyl.muted(dark))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 6)
                    VinylProgress(fraction: fraction, dark: dark)
                    Spacer(minLength: 4)
                    times(13)
                    Spacer(minLength: 6)
                    transport(size: 22)
                }
                .frame(maxHeight: .infinity)
                .padding(.trailing, 2)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .containerBackground(for: .widget) { Vinyl.paper(dark) }
        .widgetURL(BlazifyLink.player)
    }

    private var large: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                VinylRecord(artwork: entry.art, diameter: g.size.width * 0.64, angle: tilt)
                Spacer(minLength: 14)
                VStack(spacing: 2) {
                    Text(track?.title ?? "Nothing playing")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(Vinyl.ink(dark))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(track?.artist.isEmpty == false ? track!.artist : "Blazify")
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Vinyl.muted(dark))
                        .lineLimit(1)
                }
                Spacer(minLength: 14)
                VinylProgress(fraction: fraction, dark: dark)
                times(14).padding(.top, 5)
                Spacer(minLength: 12)
                transport(size: 30)
                Spacer(minLength: 2)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .containerBackground(for: .widget) { Vinyl.paper(dark) }
        .widgetURL(BlazifyLink.player)
    }

    private func times(_ size: CGFloat) -> some View {
        HStack {
            Text(SharedTrack.time(elapsed))
            Spacer(minLength: 0)
            Text(SharedTrack.time(track?.duration ?? 0))
        }
        .font(.system(size: size, weight: .semibold, design: .serif))
        .foregroundStyle(Vinyl.muted(dark))
        .monospacedDigit()
    }

    /// Interactive, and it stays inside the widget — a pause button that threw
    /// you into the app would be worse than no button at all.
    private func transport(size: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button(intent: WidgetPreviousIntent()) {
                Image(systemName: "backward.end.fill")
            }
            .accessibilityLabel("Previous")
            Spacer(minLength: 0)
            Button(intent: WidgetPlayPauseIntent()) {
                Image(systemName: track?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 1.12, weight: .heavy))
            }
            .accessibilityLabel(track?.isPlaying == true ? "Pause" : "Play")
            Spacer(minLength: 0)
            Button(intent: WidgetNextIntent()) {
                Image(systemName: "forward.end.fill")
            }
            .accessibilityLabel("Next")
        }
        .font(.system(size: size, weight: .heavy))
        .foregroundStyle(Vinyl.ink(dark))
        .buttonStyle(.plain)
        .padding(.horizontal, size * 0.45)
    }

    // MARK: Lock Screen
    //
    // These render as a vibrant monochrome stencil, so colour is thrown away and
    // fine detail turns to mush — hence a plain dial rather than the turntable.

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5).padding(3)
            Image(systemName: track?.isPlaying == true ? "waveform" : "flame.fill")
                .font(.system(size: 18, weight: .semibold))
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(BlazifyLink.player)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track?.title ?? "Blazify")
                .font(.headline)
                .lineLimit(1)
            Text(track?.artist.isEmpty == false ? track!.artist : "Nothing playing")
                .font(.caption)
                .lineLimit(1)
            ProgressView(value: min(max(fraction, 0), 1))
                .progressViewStyle(.linear)
                .tint(.white)
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(BlazifyLink.player)
    }

    private var inline: some View {
        Label(track.map { "\($0.title) — \($0.artist)" } ?? "Blazify",
              systemImage: track?.isPlaying == true ? "waveform" : "flame.fill")
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(BlazifyLink.player)
    }
}

struct BlazifyNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BlazifyNowPlaying", provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Turntable")
        .description("What's spinning, with the record, the bar and the buttons.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

// MARK: - Shortcuts

struct BlazifyEntry: TimelineEntry { let date: Date }

struct BlazifyProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlazifyEntry { BlazifyEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (BlazifyEntry) -> Void) {
        completion(BlazifyEntry(date: Date()))
    }
    /// Nothing here changes on its own, so one entry that never expires.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BlazifyEntry>) -> Void) {
        completion(Timeline(entries: [BlazifyEntry(date: Date())], policy: .never))
    }
}

/// The launcher, in the same sleeve as the turntable so a Home Screen carrying
/// both doesn't look like two different apps.
struct BlazifyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    var entry: BlazifyEntry

    private var dark: Bool { scheme == .dark }

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(spacing: 10) {
                tile("play.fill", "Play", BlazifyLink.resume)
                tile("heart.fill", "Liked", BlazifyLink.favourites)
            }
            .padding(12)
            .containerBackground(for: .widget) { Vinyl.paper(dark) }
        default:
            HStack(spacing: 10) {
                tile("play.fill", "Play", BlazifyLink.resume)
                tile("heart.fill", "Liked", BlazifyLink.favourites)
                tile("arrow.down.circle.fill", "Offline", BlazifyLink.downloads)
                tile("waveform", "Identify", BlazifyLink.recognise)
            }
            .padding(12)
            .containerBackground(for: .widget) { Vinyl.paper(dark) }
        }
    }

    private func tile(_ symbol: String, _ label: String, _ url: URL) -> some View {
        Link(destination: url) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .serif))
            }
            .foregroundStyle(Vinyl.ink(dark))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Vinyl.rail(dark))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct BlazifyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BlazifyWidget", provider: BlazifyProvider()) { entry in
            BlazifyWidgetView(entry: entry)
        }
        .configurationDisplayName("Shortcuts")
        .description("Play, liked songs, offline music, or identify what's around you.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct BlazifyWidgetBundle: WidgetBundle {
    var body: some Widget {
        BlazifyNowPlayingWidget()
        BlazifyWidget()
    }
}
