import SwiftUI
import WidgetKit

/// The Home Screen widget: four shortcuts into the app, and nothing that
/// pretends to know what's playing.
///
/// It deliberately shows no live playback. Reading the app's state needs an App
/// Group container, and free signing never provisions one — the widget gets an
/// empty store, so a progress bar and a play/pause glyph would sit there
/// permanently lying. The live now-playing card already exists for free on the
/// Lock Screen and in Control Centre.
struct BlazifyEntry: TimelineEntry { let date: Date }

struct BlazifyProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlazifyEntry { BlazifyEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (BlazifyEntry) -> Void) {
        completion(BlazifyEntry(date: Date()))
    }

    /// Nothing here changes on its own, so one entry that never expires — no
    /// refresh budget spent on what is really a launcher.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BlazifyEntry>) -> Void) {
        completion(Timeline(entries: [BlazifyEntry(date: Date())], policy: .never))
    }
}

private struct Shortcut: Identifiable {
    let id: String
    let symbol: String
    let title: LocalizedStringKey
    let url: URL
}

private let shortcuts: [Shortcut] = [
    Shortcut(id: "play", symbol: "play.fill", title: "Play", url: BlazifyLink.resume),
    Shortcut(id: "liked", symbol: "heart.fill", title: "Liked", url: BlazifyLink.favourites),
    Shortcut(id: "offline", symbol: "arrow.down.circle.fill", title: "Offline",
             url: BlazifyLink.downloads),
    Shortcut(id: "identify", symbol: "waveform", title: "Identify", url: BlazifyLink.recognise),
]

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

    /// Two by two. No header — at 155pt the wordmark would cost a whole row of
    /// tile height to say something the icon already says.
    private var small: some View {
        VStack(spacing: 8) {
            row(0..<2, icon: 19, label: 11)
            row(2..<4, icon: 19, label: 11)
        }
        .padding(12)
        .containerBackground(for: .widget) { Sleeve.paper(dark) }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            SleeveHeader(dark: dark, size: 20)
            row(0..<4, icon: 18, label: 10.5)
        }
        .padding(14)
        .containerBackground(for: .widget) { Sleeve.paper(dark) }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 14) {
            SleeveHeader(dark: dark, size: 26)
            row(0..<2, icon: 30, label: 14)
            row(2..<4, icon: 30, label: 14)
        }
        .padding(18)
        .containerBackground(for: .widget) { Sleeve.paper(dark) }
    }

    private func row(_ range: Range<Int>, icon: CGFloat, label: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(shortcuts[range]) { item in
                SleeveTile(symbol: item.symbol, title: item.title, url: item.url,
                           dark: dark, icon: icon, label: label)
            }
        }
    }

    // MARK: Lock Screen
    //
    // These render as a vibrant monochrome stencil, so colour is thrown away and
    // fine detail turns to mush — hence a symbol rather than the logo.

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
            Label("Blazify", systemImage: "flame.fill").font(.headline)
            Text("Tap to play").font(.caption)
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
