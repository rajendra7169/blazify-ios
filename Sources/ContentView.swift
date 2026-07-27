import SwiftUI

struct ContentView: View {
    @StateObject private var player = AudioPlayer()

    // A known-good test video (resolved fine through the backend). This proves the
    // whole chain: backend resolves -> phone streams real YouTube audio.
    private let testVideoId = "dQw4w9WgXcQ"

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "flame.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text(player.title)
                .font(.title3).bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(player.status)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange)
            }

            Button("Reload") { player.load(videoId: testVideoId) }
                .font(.footnote)
        }
        .padding()
        .onAppear { player.load(videoId: testVideoId) }
    }
}
