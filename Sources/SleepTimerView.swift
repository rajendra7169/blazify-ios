import SwiftUI

/// Blaze sleep-timer sheet: big readout, 15/30/45/60 chips, a minutes slider,
/// End-of-song, and a live countdown with END/RESET when running.
struct SleepTimerView: View {
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Double = 30

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
        .background(Blaze.surface.ignoresSafeArea())
        .presentationDetents([.height(player.sleepActive ? 300 : 440)])
        .preferredColorScheme(.dark)
    }

    // MARK: Picker

    private var picker: some View {
        VStack(spacing: 20) {
            Text(timeString(minutes * 60))
                .font(.system(size: 34, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white)

            Slider(value: $minutes, in: 5...120, step: 5).tint(Blaze.amber)

            HStack(spacing: 10) {
                ForEach([15, 30, 45, 60], id: \.self) { m in
                    chip(m)
                }
            }

            Button {
                player.setSleepAtEndOfSong()
                dismiss()
            } label: {
                Text("End of song")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Blaze.amber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(Capsule().stroke(Blaze.amber, lineWidth: 2))
            }

            HStack(spacing: 12) {
                pill("CANCEL", filled: false) { dismiss() }
                pill("START", filled: true) {
                    player.startSleepTimer(minutes: Int(minutes))
                    dismiss()
                }
            }
        }
    }

    // MARK: Running

    private var running: some View {
        VStack(spacing: 20) {
            Text(player.sleepAtEndOfSong ? "End of song" : timeString(player.sleepRemaining ?? 0))
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

    // MARK: Bits

    private func chip(_ m: Int) -> some View {
        let selected = Int(minutes) == m
        return Button { minutes = Double(m) } label: {
            Text("\(m)m")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.8))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(selected ? Blaze.amber : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filled ? .white : Blaze.amber)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(filled ? AnyShapeStyle(Blaze.amber) : AnyShapeStyle(Color.clear))
                .overlay(Capsule().stroke(Blaze.amber, lineWidth: filled ? 0 : 2))
                .clipShape(Capsule())
        }
    }
}

/// m:ss / h:mm:ss formatter shared by the player.
func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
