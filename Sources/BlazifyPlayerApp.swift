import SwiftUI

@main
struct BlazifyPlayerApp: App {
    init() {
        // Art is served with long cache headers, so a real disk cache means it
        // survives relaunches instead of being refetched every cold start.
        ImageCache.configureDiskCache()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
