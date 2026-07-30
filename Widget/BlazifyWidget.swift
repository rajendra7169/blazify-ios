import SwiftUI
import WidgetKit

/// The Home Screen widget. It deliberately holds no state: reading the app's
/// now-playing would need an App Group entitlement, which a free signing profile
/// may not carry, and a widget that fails to sign is worse than a simple one.
/// Every tile is a deep link the app already knows how to handle.
struct BlazifyEntry: TimelineEntry {
    let date: Date
}

struct BlazifyProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlazifyEntry { BlazifyEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (BlazifyEntry) -> Void) {
        completion(BlazifyEntry(date: Date()))
    }

    /// Nothing here changes on its own, so one entry that never expires — no
    /// refresh budget spent for a widget that is really a launcher.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BlazifyEntry>) -> Void) {
        completion(Timeline(entries: [BlazifyEntry(date: Date())], policy: .never))
    }
}

private let amber = Color(red: 1.0, green: 0.655, blue: 0.149)      // #FFA726
private let ember = Color(red: 1.0, green: 0.439, blue: 0.263)      // #FF7043

struct BlazifyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BlazifyEntry

    var body: some View {
        switch family {
        case .systemSmall: small
        default: medium
        }
    }

    /// One big play button — the thing you actually want from the Home Screen.
    private var small: some View {
        Link(destination: BlazifyLink.resume) {
            VStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Blazify")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("Tap to play")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(for: .widget) { gradient }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Blazify")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)

            HStack(spacing: 8) {
                tile("play.fill", "Play", BlazifyLink.resume)
                tile("heart.fill", "Liked", BlazifyLink.favourites)
                tile("arrow.down.circle.fill", "Offline", BlazifyLink.downloads)
                tile("waveform", "Identify", BlazifyLink.recognise)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { gradient }
    }

    private func tile(_ symbol: String, _ label: String, _ url: URL) -> some View {
        Link(destination: url) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: [amber, ember], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct BlazifyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BlazifyWidget", provider: BlazifyProvider()) { entry in
            BlazifyWidgetView(entry: entry)
        }
        .configurationDisplayName("Blazify")
        .description("Start playing, jump to your liked songs or offline music, or identify what's around you.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BlazifyWidgetBundle: WidgetBundle {
    var body: some Widget { BlazifyWidget() }
}
