import SwiftUI

/// Spotify's green, used only where their own mark is drawn.
private let spotifyGreen = Color(hex: 0x1ED760)

/// Paste a Spotify link, get the playlist here.
///
/// The work is a search per track, so it takes a while: while it runs, songs
/// travel from Spotify's mark to Blazify's, and the count says how far along it
/// is. At the end it says plainly how many were found and how many were not,
/// rather than leaving somebody to count.
struct SpotifyImportDialog: View {
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

    /// Held apart from the presentation so the scrim and the card can fade in
    /// after the cover itself is up. A cover arrives by sliding from the bottom,
    /// which is a sheet's entrance, not a dialog's — showing the contents only
    /// once it has landed turns that slide into a fade.
    @State private var shown = false

    var body: some View {
        ZStack {
            // Tapping away closes it, unless the work is already under way: half of
            // it is network calls that cannot be taken back.
            Color.black.opacity(shown ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture { if !running { close() } }

            VStack(spacing: 14) {
                TravellingSongs(
                    running: running,
                    finished: outcome != nil,
                    fraction: total > 0 ? Double(done) / Double(total) : 0)

                Text("Import from Spotify")
                    .font(.blaze(22, .bold))
                    .foregroundStyle(palette.onSurface)
                    .multilineTextAlignment(.center)

                if let result = outcome {
                    finished(result)
                } else if running {
                    progress
                } else {
                    form
                }

                buttons.padding(.top, 2)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(palette.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            .padding(.horizontal, 24)
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
        }
        .presentationBackground(.clear)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { shown = true }
        }
    }

    /// Fades out before it goes, so closing is as quiet as opening.
    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { dismiss() }
    }

    // MARK: - The three states

    private var form: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                HStack(spacing: 14) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 18))
                        .foregroundStyle(palette.onSurfaceVariant)
                    TextField("Spotify playlist link", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.blaze(16))
                        .foregroundStyle(palette.onSurface)
                        .onChange(of: link) { failure = nil }
                    if link.isEmpty {
                        // The clipboard is read on the tap, never while drawing: a
                        // body that reads it puts the system's paste notice on screen
                        // every time the view refreshes.
                        Button("Paste") {
                            if let pasted = UIPasteboard.general.string { link = pasted }
                        }
                        .font(.blaze(13, .semibold))
                        .foregroundStyle(palette.accent)
                    }
                }
                Rectangle()
                    .fill(!link.isEmpty && !looksRight
                          ? Color.red.opacity(0.7) : palette.onSurface.opacity(0.35))
                    .frame(height: 1)
            }
            .padding(.top, 4)

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
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if let result = outcome {
                if !result.songs.isEmpty {
                    textButton("Play", enabled: true) {
                        player.play(result.songs, startAt: 0)
                        close()
                    }
                }
                textButton("OK", enabled: true) { close() }
            } else {
                textButton("Cancel", enabled: !running) { close() }
                textButton("Import", enabled: looksRight && !running && auth.isLoggedIn) { start() }
            }
        }
    }

    /// The flat text buttons the Android dialogs use, in the corner of the card.
    private func textButton(_ title: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.blaze(15, .semibold))
                .foregroundStyle(enabled ? palette.accent : palette.onSurfaceVariant.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
                let result = try await SpotifyImport.run(link: link) { soFar, all in
                    done = soFar
                    total = all
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
        let shift: Double = finished ? 1 : fraction
        let spotifySize = base * CGFloat(1 - 0.18 * shift)
        let blazifySize = base * CGFloat(1 + 0.20 * shift)

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

/// Spotify's own mark.
///
/// The same path the Android app draws, taken from their vector unaltered — a
/// brand's mark redrawn by hand is a different mark, and the arcs this used to
/// approximate looked it.
struct SpotifyMark: View {
    /// Spotify's mark as vector path data, on a 24pt viewport.
    private static let mark = "M12,0C5.4,0 0,5.4 0,12s5.4,12 12,12 12,-5.4 12,-12S18.66,0 12,0zM17.521,17.34c-0.24,0.359 -0.66,0.48 -1.021,0.24 -2.82,-1.74 -6.36,-2.101 -10.561,-1.141 -0.418,0.122 -0.779,-0.179 -0.899,-0.539 -0.12,-0.421 0.18,-0.78 0.54,-0.9 4.56,-1.021 8.52,-0.6 11.64,1.32 0.42,0.18 0.479,0.659 0.301,1.02zM18.961,14.04c-0.301,0.42 -0.841,0.6 -1.262,0.3 -3.239,-1.98 -8.159,-2.58 -11.939,-1.38 -0.479,0.12 -1.02,-0.12 -1.14,-0.6 -0.12,-0.48 0.12,-1.021 0.6,-1.141 4.34,-1.319 9.74,-0.659 13.46,1.62 0.361,0.181 0.54,0.78 0.241,1.2zM19.081,10.68C15.24,8.4 8.82,8.16 5.16,9.301c-0.6,0.179 -1.2,-0.181 -1.38,-0.721 -0.18,-0.601 0.18,-1.2 0.72,-1.381 4.26,-1.26 11.28,-1.02 15.721,1.621 0.539,0.3 0.719,1.02 0.419,1.56 -0.299,0.421 -1.02,0.599 -1.559,0.3z"

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            VectorPath.path(Self.mark, side: side)
                .fill(spotifyGreen)
                .frame(width: side, height: side)
        }
    }
}
