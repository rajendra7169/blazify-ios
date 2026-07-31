import SwiftUI
import WidgetKit

/// The Home Screen widget.
///
/// It shows no live playback on purpose. Reading what the app is playing needs
/// an App Group container, and free signing never provisions one — the widget
/// gets an empty store, so a progress bar and a play/pause glyph would sit there
/// permanently lying. Everything here is either true or a link that works.
struct BlazifyEntry: TimelineEntry { let date: Date }

struct BlazifyProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlazifyEntry { BlazifyEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (BlazifyEntry) -> Void) {
        completion(BlazifyEntry(date: Date()))
    }

    /// Nothing here changes on its own, so one entry that never expires — no
    /// refresh budget spent on a widget that is really a launcher.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BlazifyEntry>) -> Void) {
        completion(Timeline(entries: [BlazifyEntry(date: Date())], policy: .never))
    }
}

struct BlazifyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    var entry: BlazifyEntry

    private var dark: Bool { scheme == .dark }

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .systemLarge: large
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    // MARK: Home Screen

    /// The record, and the app's name under it. One tap, straight into playing.
    private var small: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                VinylRecord(diameter: g.size.width * 0.74)
                Spacer(minLength: 8)
                wordmark(16)
                Text("Tap to play")
                    .font(.system(size: 11.5, weight: .semibold, design: .serif))
                    .foregroundStyle(Vinyl.muted(dark))
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
        }
        .padding(14)
        .containerBackground(for: .widget) { Vinyl.paper(dark) }
        .widgetURL(BlazifyLink.resume)
    }

    /// Record on the left at full height, the four things worth a shortcut on
    /// the right — each its own tap target, not a decoration.
    private var medium: some View {
        GeometryReader { g in
            HStack(spacing: 14) {
                VinylRecord(diameter: g.size.height * 0.96)
                VStack(alignment: .leading, spacing: 8) {
                    wordmark(19)
                    grid(icon: 15, label: 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .containerBackground(for: .widget) { Vinyl.paper(dark) }
    }

    private var large: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                VinylRecord(diameter: g.size.width * 0.60)
                Spacer(minLength: 16)
                wordmark(26)
                Text("Your music, on fire")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(Vinyl.muted(dark))
                Spacer(minLength: 18)
                grid(icon: 21, label: 12)
                    .frame(height: g.size.height * 0.3)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .containerBackground(for: .widget) { Vinyl.paper(dark) }
    }

    private func wordmark(_ size: CGFloat) -> some View {
        Text("Blazify")
            .font(.system(size: size, weight: .bold, design: .serif))
            .foregroundStyle(Vinyl.ink(dark))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func grid(icon: CGFloat, label: CGFloat) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                tile("play.fill", "Play", BlazifyLink.resume, icon, label)
                tile("heart.fill", "Liked", BlazifyLink.favourites, icon, label)
            }
            HStack(spacing: 7) {
                tile("arrow.down.circle.fill", "Offline", BlazifyLink.downloads, icon, label)
                tile("waveform", "Identify", BlazifyLink.recognise, icon, label)
            }
        }
    }

    private func tile(_ symbol: String, _ title: String, _ url: URL,
                      _ icon: CGFloat, _ label: CGFloat) -> some View {
        Link(destination: url) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: icon, weight: .semibold))
                Text(title)
                    .font(.system(size: label, weight: .semibold, design: .serif))
                    .lineLimit(1)
            }
            .foregroundStyle(Vinyl.ink(dark))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Vinyl.rail(dark))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .accessibilityLabel(title)
    }

    // MARK: Lock Screen
    //
    // These render as a vibrant monochrome stencil, so colour is thrown away and
    // fine detail turns to mush — hence a symbol rather than the turntable.

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5).padding(3)
            Image(systemName: "flame.fill")
                .font(.system(size: 19, weight: .semibold))
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(BlazifyLink.resume)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Blazify", systemImage: "flame.fill")
                .font(.headline)
            Text("Tap to play")
                .font(.caption)
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(BlazifyLink.resume)
    }

    private var inline: some View {
        Label("Blazify", systemImage: "flame.fill")
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(BlazifyLink.resume)
    }
}

struct BlazifyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BlazifyWidget", provider: BlazifyProvider()) { entry in
            BlazifyWidgetView(entry: entry)
        }
        .configurationDisplayName("Blazify")
        .description("Play, liked songs, offline music, or identify what's around you.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

@main
struct BlazifyWidgetBundle: WidgetBundle {
    var body: some Widget { BlazifyWidget() }
}
