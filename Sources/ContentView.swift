import SwiftUI

struct ContentView: View {
    @StateObject private var player = AudioPlayer()

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "flame.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)

            Text(player.title)
                .font(.title2).bold()

            Text(player.isPlaying ? "Playing" : "Paused")
                .foregroundStyle(.secondary)

            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .onAppear { player.prepare() }
    }
}
