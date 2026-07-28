import SwiftUI

/// Blaze sleep-timer sheet, ported from BlazeSleepTimerDialog.kt: a big readout,
/// a minutes slider with 15/30/45/60 chips, "End of song", a "± N songs" stepper,
/// and a live countdown with END / RESET while it runs.
struct SleepTimerView: View {
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Double = 30
    @State private var songs = 0     // 0 = minutes mode
    @State private var sheetHeight: CGFloat = 420

    private var songsMode: Bool { songs > 0 }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 30))
                .foregroundStyle(Blaze.amber)

            if player.sleepActive {
                running
            } else {
                picker
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        // Measure the content and make the sheet exactly that tall. The old
        // fixed 520/300 detents were taller than the content, which is the
        // empty band that showed up along the bottom.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { sheetHeight = geo.size.height }
                    .onChange(of: geo.size.height) { sheetHeight = geo.size.height }
            },
        )
        .background(Blaze.surface)
        // One surface for the whole sheet — the safe-area edges were painting
        // their own colours before, so the top, middle and bottom disagreed.
        .presentationBackground(Blaze.surface)
        .presentationDetents([.height(sheetHeight)])
        .preferredColorScheme(.dark)
    }

    // MARK: Picker

    private var picker: some View {
        VStack(spacing: 18) {
            Text(songsMode ? "\(songs) song\(songs == 1 ? "" : "s")" : timeString(minutes * 60))
                .font(.system(size: 34, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white)

            Slider(value: $minutes, in: 5...120, step: 5)
                .tint(Blaze.amber)
                .disabled(songsMode)
                .opacity(songsMode ? 0.35 : 1)
                .onChange(of: minutes) { songs = 0 }   // touching minutes leaves songs mode

            HStack(spacing: 10) {
                ForEach([15, 30, 45, 60], id: \.self) { m in
                    chip(m)
                }
            }

            HStack(spacing: 12) {
                Button {
                    player.setSleepAtEndOfSong()
                    dismiss()
                } label: {
                    Text("End of song")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Blaze.amber)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .overlay(RoundedRectangle(cornerRadius: 24)
                            .stroke(Blaze.amber, lineWidth: 2))
                }

                songsStepper
            }

            HStack(spacing: 12) {
                pill("CANCEL", filled: false) { dismiss() }
                pill("START", filled: true) {
                    if songsMode {
                        player.startSleepAfterSongs(songs)
                    } else {
                        player.startSleepTimer(minutes: Int(minutes))
                    }
                    dismiss()
                }
            }
        }
    }

    /// "− N songs +" — bordered pill, matching the Android stepper.
    private var songsStepper: some View {
        HStack(spacing: 6) {
            stepButton("minus") { songs = max(0, songs - 1) }
            Text(songs == 0 ? "songs" : "\(songs)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(songsMode ? Blaze.amber : .white.opacity(0.6))
                .frame(minWidth: 44)
            stepButton("plus") { songs += 1 }
        }
        .padding(.horizontal, 6)
        .frame(height: 46)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Blaze.amber, lineWidth: 2))
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Blaze.amber)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    // MARK: Running

    private var running: some View {
        VStack(spacing: 20) {
            Text(runningLabel)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            HStack(spacing: 12) {
                pill("END", filled: false) {
                    player.cancelSleepTimer()
                    dismiss()
                }
                pill("RESET", filled: true) {
                    player.cancelSleepTimer()   // back to the picker
                }
            }
        }
    }

    private var runningLabel: String {
        if player.sleepAtEndOfSong { return "End of song" }
        if let left = player.sleepSongsRemaining { return "\(left) song\(left == 1 ? "" : "s")" }
        return timeString(player.sleepRemaining ?? 0)
    }

    // MARK: Bits

    private func chip(_ m: Int) -> some View {
        let selected = !songsMode && Int(minutes) == m
        return Button {
            songs = 0
            minutes = Double(m)
        } label: {
            Text("\(m)m")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.8))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(selected ? AnyShapeStyle(Blaze.amber)
                                     : AnyShapeStyle(Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filled ? .white : Blaze.amber)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(filled ? AnyShapeStyle(Blaze.amber) : AnyShapeStyle(Color.clear))
                .overlay(Capsule().stroke(Blaze.amber, lineWidth: filled ? 0 : 2))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// m:ss / h:mm:ss formatter shared by the player.
func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
