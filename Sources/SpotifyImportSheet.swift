import SwiftUI

/// Spotify's green, used only where their own mark is drawn.
private let spotifyGreen = Color(hex: 0x1ED760)

/// Paste a Spotify link, get the playlist here.
///
/// The work is a search per track, so it takes a while: while it runs, songs
/// travel from Spotify's mark to Blazify's, and the count says how far along it
/// is. At the end it says plainly how many were found and how many were not,
/// rather than leaving somebody to count.
struct SpotifyImportSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var player: Player
    /// Called once a playlist has been created, so the list behind the sheet
    /// shows it without waiting for a sign-in change.
    var onImported: () -> Void = {}
    @ObservedObject private var auth = Auth.shared

    @State private var link = ""
    @State private var running = false
    @State private var done = 0
    @State private var total = 0
    @State private var outcome: SpotifyImport.Outcome?
    @State private var failure: String?

    private var looksRight: Bool { SpotifyPlaylist.parseLink(link) != nil }

    var body: some View {
        VStack(spacing: 16) {
            TravellingSongs(
                running: running,
                finished: outcome != nil,
                fraction: total > 0 ? Double(done) / Double(total) : 0)

            Text("Import from Spotify")
                .font(.blaze(22, .bold))
                .foregroundStyle(palette.onSurface)

            if let result = outcome {
                finished(result)
            } else if running {
                progress
            } else {
                form
            }

            buttons
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .presentationBackground(.regularMaterial)
        .presentationDetents([.medium, .large])
        // Half the work is network calls that cannot be taken back; closing the
        // sheet mid-import is refused rather than left running invisibly.
        .interactiveDismissDisabled(running)
    }

    // MARK: - The three states

    private var form: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(palette.onSurfaceVariant)
                TextField("Spotify playlist link", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .foregroundStyle(palette.onSurface)
                    .onChange(of: link) { failure = nil }
                if let pasted = UIPasteboard.general.string, SpotifyPlaylist.parseLink(pasted) != nil, link.isEmpty {
                    Button("Paste") { link = pasted }
                        .font(.blaze(13, .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(palette.onSurface.opacity(0.08))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    !link.isEmpty && !looksRight ? Color.red.opacity(0.7) : .clear,
                    lineWidth: 1))

            if let failure {
                note(failure, color: .red)
            } else if !auth.isLoggedIn {
                note("Sign in to import a playlist — it is kept on your account.")
            } else {
                note("Open the playlist in Spotify, tap Share, then Copy link. The playlist has to be public.")
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 12) {
            Text(total == 0 ? "Reading the playlist…" : "Looking for song \(done) of \(total)…")
                .font(.blaze(14))
                .foregroundStyle(palette.onSurface)
            if total == 0 {
                ProgressView().tint(palette.accent)
            } else {
                ProgressView(value: Double(done), total: Double(total))
                    .tint(palette.accent)
            }
        }
    }

    private func finished(_ result: SpotifyImport.Outcome) -> some View {
        VStack(spacing: 10) {
            Text("Found \(result.matched) of \(result.total) songs.")
                .font(.blaze(14))
                .foregroundStyle(palette.onSurface)
            if !result.missing.isEmpty {
                note("Not found: " + result.missing.prefix(5).joined(separator: ", "))
            }
            if result.mayHaveMore {
                note("Spotify only shares the first 100 songs of a playlist, so anything after that was not imported.")
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            if let result = outcome {
                if !result.songs.isEmpty {
                    pill("Play", filled: false) {
                        player.play(result.songs, startAt: 0)
                        dismiss()
                    }
                }
                pill("Done", filled: true) { dismiss() }
            } else {
                pill("Cancel", filled: false) { dismiss() }
                    .disabled(running)
                    .opacity(running ? 0.5 : 1)
                pill("Import", filled: true) { start() }
                    .disabled(!looksRight || running || !auth.isLoggedIn)
                    .opacity(!looksRight || running || !auth.isLoggedIn ? 0.5 : 1)
            }
        }
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.blaze(15, .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(filled ? palette.accent : palette.onSurface.opacity(0.10))
                .foregroundStyle(filled ? .black : palette.onSurface)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(.blaze(12))
            .foregroundStyle(color ?? palette.onSurfaceVariant)
            .multilineTextAlignment(.center)
    }

    private func start() {
        running = true
        failure = nil
        done = 0
        total = 0
        // On the main actor throughout: the progress counters and the outcome are
        // view state, and the searches are network calls that suspend anyway.
        Task { @MainActor in
            do {
                let result = try await SpotifyImport.run(link: link) { finished, count in
                    done = finished
                    total = count
                }
                outcome = result
                onImported()
            } catch {
                failure = error.localizedDescription
            }
            running = false
        }
    }
}

/// Spotify on one side, Blazify on the other, and the songs crossing between them.
///
/// They start level. As songs arrive the weight shifts: Blazify grows, Spotify
/// settles back, and both glow while the work is going on. When it finishes the
/// glow stops, which is how the picture says "done" without a word.
private struct TravellingSongs: View {
    @Environment(\.palette) private var palette
    let running: Bool
    let finished: Bool
    let fraction: Double

    private let base: CGFloat = 56

    var body: some View {
        let shift = finished ? 1 : fraction
        let spotifySize = base * (1 - 0.18 * shift)
        let blazifySize = base * (1 + 0.20 * shift)

        TimelineView(.animation(minimumInterval: 1 / 30, paused: !running)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            // One slow breath for the glow, one lap of the gap for the notes.
            let pulse = 0.5 + 0.5 * sin(time * 2 * .pi / 1.4)
            let lap = (time / 2.2).truncatingRemainder(dividingBy: 1)

            HStack(spacing: 0) {
                badge(size: spotifySize,
                      glow: running ? 0.45 + 0.55 * pulse : 0,
                      colour: spotifyGreen) {
                    SpotifyMark().frame(width: spotifySize, height: spotifySize)
                }

                notes(lap: lap)
                    .frame(height: base)
                    .padding(.horizontal, 6)

                badge(size: blazifySize,
                      glow: running ? 0.45 + 0.55 * (1 - pulse) : 0,
                      colour: palette.accent) {
                    // The flame sits inside its own margin, so it is drawn a
                    // little larger to stand level with Spotify's mark.
                    Image(bundleImage: "blaze_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: blazifySize * 1.22, height: blazifySize * 1.22)
                }
            }
        }
        .frame(height: base * 1.6)
        .animation(.easeInOut(duration: 0.6), value: shift)
    }

    /// Nothing is drawn between the two marks but the songs on their way across.
    private func notes(lap: Double) -> some View {
        Canvas { context, canvas in
            guard running else { return }
            let count = 5
            for index in 0..<count {
                // Each note starts a fifth of a lap after the one before it, so
                // they arrive one at a time rather than in a clump.
                let position = CGFloat((lap + Double(index) / Double(count))
                    .truncatingRemainder(dividingBy: 1))
                let lift = sin(position * .pi)
                let radius = 2.5 + 2 * lift
                let fade = max(0, min(1, 1 - abs(position - 0.5) * 1.6))
                // A fixed wobble per note, so they do not all fly the same arc.
                let wobble = 0.6 + 0.4 * CGFloat(index * 7 % 5) / 4
                let centre = CGPoint(
                    x: position * canvas.width,
                    y: canvas.height / 2 - lift * canvas.height * 0.22 * wobble)
                let dot = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                 width: radius * 2, height: radius * 2))
                context.fill(dot, with: .color((index % 2 == 0 ? palette.accent : spotifyGreen)
                    .opacity(Double(fade))))
            }
        }
    }

    private func badge<Content: View>(size: CGFloat, glow: Double, colour: Color,
                                      @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            if glow > 0.01 {
                Circle()
                    .fill(RadialGradient(colors: [colour.opacity(0.38 * glow), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.78))
                    .frame(width: size * 1.55, height: size * 1.55)
            }
            content()
        }
        .frame(width: size, height: size)
    }
}

/// Spotify's mark, drawn rather than shipped: three waves on a green circle.
private struct SpotifyMark: View {
    var body: some View {
        Canvas { context, canvas in
            let side = min(canvas.width, canvas.height)
            context.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: side, height: side)),
                         with: .color(spotifyGreen))

            // The three waves share a centre below the mark, so each one bows
            // upward — the widest at the top, the shortest at the bottom.
            let centre = CGPoint(x: side / 2, y: side * 0.95)
            let waves: [(radius: CGFloat, width: CGFloat, span: CGFloat)] = [
                (side * 0.62, side * 0.105, 0.58),
                (side * 0.45, side * 0.085, 0.54),
                (side * 0.29, side * 0.070, 0.50),
            ]
            for wave in waves {
                let half = CGFloat.pi * wave.span / 2
                var path = Path()
                path.addArc(center: centre, radius: wave.radius,
                            startAngle: .radians(Double(-.pi / 2 - half)),
                            endAngle: .radians(Double(-.pi / 2 + half)),
                            clockwise: false)
                context.stroke(path, with: .color(.black.opacity(0.9)),
                               style: StrokeStyle(lineWidth: wave.width, lineCap: .round))
            }
        }
    }
}
