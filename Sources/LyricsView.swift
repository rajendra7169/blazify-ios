import SwiftUI
import UIKit

/// Full-screen synced lyrics, Blaze-style: album-art gradient background, the
/// current line at full white with a distance-based fade on the rest, auto-scrolled
/// to center; tap a line to seek. The "Language" button switches lyric versions.
struct LyricsView: View {
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [LyricsCandidate] = []
    @State private var result: LyricsResult?
    @State private var loading = true
    @State private var showVersions = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [player.artColor, player.artColor.opacity(0.4), .black],
                startPoint: .top, endPoint: .bottom,
            )
            .overlay(Color.black.opacity(0.25))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: player.artColor)

            VStack(spacing: 0) {
                topBar
                content
            }
            .foregroundStyle(.white)
        }
        .task(id: player.current?.videoId) { await load() }
        .sheet(isPresented: $showVersions) {
            LyricsVersionPicker(candidates: candidates, current: result) { pick in
                result = pick.result
                showVersions = false
            }
        }
    }

    // MARK: Top bar (close + centered Language button)

    private var topBar: some View {
        ZStack {
            Button { showVersions = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "character.bubble")
                    Text("Language")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            }
            .disabled(candidates.count < 2)
            .opacity(candidates.count < 2 ? 0.5 : 1)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if loading {
            Spacer(); ProgressView().tint(.white).scaleEffect(1.3); Spacer()
        } else if let result, result.synced, !result.lines.isEmpty {
            syncedLyrics(result.lines)
        } else if let plain = result?.plain, !plain.isEmpty {
            ScrollView {
                Text(plain)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(8)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24).padding(.vertical, 40)
            }
        } else {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "music.note.list").font(.system(size: 40)).opacity(0.5)
                Text("Lyrics not found").foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
    }

    private func syncedLyrics(_ lines: [LyricLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .center, spacing: 22) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { pair in
                        let distance = abs(pair.offset - (activeIndex ?? -100))
                        Text(pair.element.text.isEmpty ? "♪" : pair.element.text)
                            .font(.system(size: 27, weight: .bold))
                            .tracking(-0.5)
                            .foregroundStyle(.white.opacity(alpha(distance)))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .id(pair.offset)
                            .animation(.easeInOut(duration: 0.25), value: distance)
                            .onTapGesture {
                                guard player.duration > 0 else { return }
                                player.seek(to: pair.element.time / player.duration)
                            }
                    }
                }
                .padding(.horizontal, 26)
                // Big top/bottom insets so the active line can sit centered.
                .padding(.vertical, UIScreen.main.bounds.height * 0.4)
            }
            .onChange(of: activeIndex) {
                guard let i = activeIndex else { return }
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(i, anchor: .center) }
            }
        }
    }

    /// Blaze's fade ladder: active line solid, neighbours progressively dimmer.
    private func alpha(_ distance: Int) -> Double {
        switch distance {
        case 0: return 1.0
        case 1: return 0.4
        case 2: return 0.28
        case 3: return 0.2
        case 4: return 0.14
        default: return 0.1
        }
    }

    /// Index of the last line whose timestamp has passed.
    private var activeIndex: Int? {
        guard let lines = result?.lines, !lines.isEmpty else { return nil }
        let t = player.currentTime + 0.2
        var idx: Int?
        for (i, line) in lines.enumerated() {
            if line.time <= t { idx = i } else { break }
        }
        return idx
    }

    private func load() async {
        loading = true
        result = nil
        candidates = []
        guard let track = player.current else { loading = false; return }
        let found = await Lyrics.search(title: track.title, artist: track.artist)
        await MainActor.run {
            candidates = found
            result = Lyrics.best(found)
            loading = false
        }
    }
}

/// Version/source picker opened by the Language button.
private struct LyricsVersionPicker: View {
    let candidates: [LyricsCandidate]
    let current: LyricsResult?
    let onPick: (LyricsCandidate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates) { c in
                    Button { onPick(c) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.trackName).foregroundStyle(.white).lineLimit(1)
                                Text(c.artistName).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                            }
                            Spacer()
                            if c.synced {
                                Image(systemName: "waveform").foregroundStyle(Blaze.amber).font(.caption)
                            }
                            if c.result == current {
                                Image(systemName: "checkmark").foregroundStyle(Blaze.amber)
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Blaze.scaffold.ignoresSafeArea())
            .navigationTitle("Lyrics version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Blaze.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
