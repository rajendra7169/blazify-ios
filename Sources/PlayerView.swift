import SwiftUI
import UIKit

/// Full-screen Blazify player — a SwiftUI port of the Android Blaze CLASSIC layout:
/// album-art gradient background, centered "Now Playing" header, square art (r20),
/// title + favorite + ⋮, the slim Apple-Music slider, the classic transport row
/// (shuffle · prev · 72pt play · next · repeat), and a Queue / Sleep / Lyrics row.
struct PlayerView: View {
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    @State private var scrub: Double?
    @State private var showQueue = false
    @State private var showSleep = false
    @State private var showLyrics = false
    @State private var showDesign = false

    var body: some View {
        // Smaller than before so the controls below get more room.
        let art = min(UIScreen.main.bounds.width - 96, 320)

        ZStack {
            // Dynamic gradient built from the song's color (amber fallback).
            LinearGradient(
                colors: [player.artColor, player.artColor.opacity(0.45), .black],
                startPoint: .top, endPoint: .bottom,
            )
            .overlay(Color.black.opacity(0.2))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: player.artColor)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)
                albumArt(side: art)
                Spacer(minLength: 22)      // art → title/progress group
                titleAndProgress
                Spacer(minLength: 30)      // group → transport (generous)
                transport
                Spacer(minLength: 24)      // transport → bottom row
                bottomRow
            }
            .padding(.top, 6)
            .padding(.bottom, 16)
            .foregroundStyle(.white)
        }
        // Swipe down anywhere to close/minimize (child gestures like the slider win locally).
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { g in
                    if g.translation.height > 90, g.translation.height > abs(g.translation.width) {
                        dismiss()
                    }
                },
        )
        .fullScreenCover(isPresented: $showLyrics) { LyricsView(player: player) }
        .sheet(isPresented: $showDesign) { PlayerDesignSheet() }
        .sheet(isPresented: $showQueue) { QueueView(player: player) }
        .sheet(isPresented: $showSleep) { SleepTimerView(player: player) }
    }

    // MARK: Header (chevron-down to close + centered "Now Playing")

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Now Playing")
                    .font(.system(size: 16, weight: .semibold))
                Text(player.current?.artist ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.8)
                    .lineLimit(1)
            }
            .padding(.horizontal, 48)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: Album art

    /// Request a larger image for the big full-screen art than the 720 the rails use.
    private var hiResArtURL: URL? {
        guard let raw = player.current?.thumbnail, !raw.isEmpty else { return nil }
        if let r = raw.range(of: "=w[0-9]+-h[0-9]+", options: .regularExpression) {
            return URL(string: raw.replacingCharacters(in: r, with: "=w1080-h1080"))
        }
        return URL(string: raw)
    }

    private func albumArt(side: CGFloat) -> some View {
        RemoteImage(url: hiResArtURL) {
            ZStack {
                Blaze.gradient
                Image(systemName: "music.note")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .overlay {
            if player.isLoading {
                ProgressView().tint(.white).scaleEffect(1.4)
            }
        }
    }

    // MARK: Title + progress (tight group under the art)

    private var titleAndProgress: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.current?.title ?? "")
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                    Text(player.current?.artist ?? "")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Button { player.toggleFavorite() } label: {
                    Image(systemName: player.isCurrentFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 26))
                        .foregroundStyle(player.isCurrentFavorite ? .red : .white)
                }

                Button { showDesign = true } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(Color.white)
                        .clipShape(Circle())
                }

                Menu {
                    if let url = shareURL {
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                    Button { player.toggleFavorite() } label: {
                        Label(player.isCurrentFavorite ? "Remove from Favorites" : "Add to Favorites",
                              systemImage: "heart")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 32)

            if let err = player.lastError {
                Text(err)
                    .font(.caption2).foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32).padding(.top, 8)
            }

            Spacer().frame(height: 24)

            SlimSlider(
                value: Binding(get: { scrub ?? player.progress }, set: { scrub = $0 }),
                active: player.artColor,
            ) { v in
                player.seek(to: v)
                scrub = nil
            }
            .padding(.horizontal, 32)

            HStack {
                Text(timeString((scrub ?? player.progress) * player.duration))
                Spacer()
                Text(timeString(player.duration))
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 36)
            .padding(.top, 6)
        }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            sideButton("shuffle", active: player.isShuffled) { player.toggleShuffle() }
            sideButton("backward.end.fill") { player.prev() }

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 72, height: 72)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: player.isPlaying ? 24 : 36))
                    .animation(.easeInOut(duration: 0.15), value: player.isPlaying)
            }
            .padding(.horizontal, 8)

            sideButton("forward.end.fill") { player.next() }
            sideButton(player.repeatMode == .one ? "repeat.1" : "repeat",
                       active: player.repeatMode != .off) { player.cycleRepeat() }
        }
        .padding(.horizontal, 32)
    }

    private func sideButton(_ icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(active ? Blaze.amber : .white)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Bottom row (Queue · Sleep · Lyrics)

    private var bottomRow: some View {
        HStack(spacing: 0) {
            bottomButton("list.bullet", "Queue") { showQueue = true }
            bottomButton(player.sleepActive ? "moon.zzz.fill" : "moon.zzz",
                         sleepLabel, active: player.sleepActive) { showSleep = true }
            bottomButton("quote.bubble", "Lyrics") { showLyrics = true }
        }
        .padding(.horizontal, 20)
    }

    private func bottomButton(_ icon: String, _ label: String,
                              active: Bool = false, dimmed: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 11)).lineLimit(1)
            }
            .foregroundStyle(active ? Blaze.amber : .white.opacity(dimmed ? 0.35 : 0.85))
            .frame(maxWidth: .infinity)
        }
        .disabled(dimmed)
    }

    private var sleepLabel: String {
        if player.sleepAtEndOfSong { return "End of song" }
        if let r = player.sleepRemaining { return timeString(r) }
        return "Sleep timer"
    }

    private var shareURL: URL? {
        guard let id = player.current?.videoId else { return nil }
        return URL(string: "https://music.youtube.com/watch?v=\(id)")
    }
}
