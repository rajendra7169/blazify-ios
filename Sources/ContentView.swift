import SwiftUI

struct ContentView: View {
    @StateObject private var player = AudioPlayer()

    // Known-good test song for now. Search (pick any song) comes next.
    private let testVideoId = "dQw4w9WgXcQ"

    var body: some View {
        PlayerView(player: player)
            .onAppear { player.load(videoId: testVideoId) }
    }
}
