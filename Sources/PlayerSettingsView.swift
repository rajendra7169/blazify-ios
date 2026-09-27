import SwiftUI

/// Settings → Player and audio. Options
/// that iOS handles itself are left out rather than shown dead: audio offload
/// (AVFoundation decides), stop-on-task-clear (no such lifecycle), pause-on-mute
/// (the hardware switch isn't observable), and skip-silence (needs an ExoPlayer
/// audio processor with no AVPlayer equivalent). Google Cast becomes AirPlay,
/// which the system route picker already offers from the player.
struct PlayerSettingsView: View {
    @ObservedObject private var prefs = PlaybackPrefs.shared
    @State private var showQuality = false
    @State private var showHistory = false
    @State private var showSponsorCategories = false

    /// What the toggle's companion row reads: the kinds of stretch chosen, or
    /// nothing at all.
    private var sponsorSummary: String {
        let chosen = SponsorBlock.Category.allCases
            .filter { prefs.sponsorCategories.contains($0.rawValue) }
            .map(\.title)
        return chosen.isEmpty ? String(localized: "None") : chosen.joined(separator: ", ")
    }

    var body: some View {
        SettingsPage(title: "Player and audio") {
            SettingsGroup(title: "Audio") {
                SettingsLink(symbol: "waveform", title: "Audio quality",
                             subtitle: prefs.quality.title) { showQuality = true }
                SettingsDivider()
                SettingsToggle(symbol: "speaker.wave.2", title: "Volume normalisation",
                               subtitle: "Even out loudness between songs",
                               isOn: $prefs.normalizeVolume)
                if prefs.normalizeVolume {
                    SettingsDivider()
                    SettingsSlider(symbol: "dial.medium", title: "Target loudness",
                                   value: $prefs.loudnessTarget, range: -24...(-6), step: 1) {
                        "\(Int($0)) LUFS"
                    }
                }
                SettingsDivider()
                SettingsSlider(symbol: "gauge.with.dots.needle.67percent",
                               title: "Playback speed", value: $prefs.speed,
                               range: PlaybackPrefs.speedRange, step: 0.05) {
                    String(format: "%.2f×", $0)
                }
                SettingsDivider()
                SettingsToggle(symbol: "tuningfork", title: "Keep pitch",
                               subtitle: "Stop voices rising as the speed goes up",
                               isOn: $prefs.preservePitch)
                SettingsDivider()
                SettingsToggle(symbol: "arrow.triangle.merge", title: "Gapless",
                               subtitle: "No silence between tracks on a live album or a mix",
                               isOn: $prefs.gapless)
                SettingsDivider()
                SettingsToggle(symbol: "arrow.left.arrow.right", title: "Crossfade",
                               subtitle: "Blend the end of one song into the next",
                               isOn: $prefs.crossfade)
                if prefs.crossfade {
                    SettingsDivider()
                    SettingsSlider(symbol: "timer", title: "Crossfade length",
                                   value: $prefs.crossfadeDuration,
                                   range: PlaybackPrefs.crossfadeRange, step: 0.5) {
                        String(format: "%.1f s", $0)
                    }
                }
            }

            SettingsGroup(title: "Video") {
                SettingsToggle(symbol: "antenna.radiowaves.left.and.right",
                               title: "Video on mobile data",
                               subtitle: "The Video Art player fetches a picture as well as the song. Off, it shows the cover instead until you are on Wi-Fi.",
                               isOn: $prefs.videoOnMobile)
            }

            SettingsGroup(title: "Skipping") {
                SettingsToggle(symbol: "forward.frame",
                               title: "Skip the parts that are not the song",
                               subtitle: "Uses SponsorBlock's community marks to jump talking, credits and sponsor breaks in music videos. Blazify asks by a few characters of a code, so the server is never told what you are playing.",
                               isOn: $prefs.sponsorBlock)
                if prefs.sponsorBlock {
                    SettingsDivider()
                    SettingsLink(symbol: "checklist", title: "What to skip",
                                 subtitle: sponsorSummary) { showSponsorCategories = true }
                }
            }

            SettingsGroup(title: "Queue") {
                SettingsToggle(symbol: "arrow.clockwise", title: "Remember the queue",
                               subtitle: "Pick up where you left off after a restart",
                               isOn: $prefs.persistentQueue)
                SettingsDivider()
                SettingsToggle(symbol: "play.circle", title: "Autoplay",
                               subtitle: "Keep playing when the queue runs out",
                               isOn: $prefs.autoplay)
                if prefs.autoplay {
                    SettingsDivider()
                    SettingsToggle(symbol: "dot.radiowaves.left.and.right",
                                   title: "Start a radio",
                                   subtitle: "Continue with songs related to the last one",
                                   isOn: $prefs.autoRadioQueue)
                }
                SettingsDivider()
                SettingsToggle(symbol: "arrow.down.circle", title: "Load more automatically",
                               subtitle: "Pull the next page as you near the end of a list",
                               isOn: $prefs.autoLoadMore)
                SettingsDivider()
                SettingsToggle(symbol: "rectangle.stack.badge.minus",
                               title: "No duplicates",
                               subtitle: "Skip a song that's already queued",
                               isOn: $prefs.preventDuplicates)
                SettingsDivider()
                SettingsToggle(symbol: "shuffle", title: "Remember shuffle and repeat",
                               subtitle: "Carry both across queues and restarts",
                               isOn: $prefs.rememberShuffleRepeat)
                SettingsDivider()
                SettingsToggle(symbol: "shuffle.circle", title: "Shuffle playlists on open",
                               subtitle: "Start a playlist shuffled rather than in order",
                               isOn: $prefs.shufflePlaylistFirst)
                SettingsDivider()
                SettingsToggle(symbol: "forward.end", title: "Skip on error",
                               subtitle: "Move to the next song if one won't play",
                               isOn: $prefs.autoSkipOnError)
            }

            SettingsGroup(title: "Sleep timer") {
                SettingsSlider(symbol: "moon.zzz", title: "Default length",
                               value: $prefs.sleepDefaultMinutes, range: 5...120, step: 5) {
                    "\(Int($0)) min"
                }
                SettingsDivider()
                SettingsToggle(symbol: "speaker.wave.1", title: "Fade out",
                               subtitle: "Ease the volume down as the timer ends",
                               isOn: $prefs.sleepFadeOut)
                SettingsDivider()
                SettingsToggle(symbol: "music.note", title: "Finish the song",
                               subtitle: "Let the current song end before stopping",
                               isOn: $prefs.sleepStopAfterSong)
            }

            SettingsGroup(title: "Other") {
                SettingsToggle(symbol: "arrow.down.heart", title: "Download on like",
                               subtitle: "Save a song offline when you favourite it",
                               isOn: $prefs.autoDownloadOnLike)
                SettingsDivider()
                SettingsToggle(symbol: "sun.max", title: "Keep the screen on",
                               subtitle: "While the full player is open",
                               isOn: $prefs.keepScreenOn)
                SettingsDivider()
                SettingsToggle(symbol: "headphones", title: "Resume on Bluetooth",
                               subtitle: "Start playing again when headphones reconnect",
                               isOn: $prefs.resumeOnBluetooth)
                SettingsDivider()
                SettingsLink(symbol: "clock.arrow.circlepath", title: "Keep history for",
                             subtitle: PlaybackPrefs.historyTitle(prefs.historyDays)) {
                    showHistory = true
                }
            }
        }
        .sheet(isPresented: $showQuality) {
            EnumPickerSheet(title: "Audio quality", options: AudioQuality.allCases,
                            label: { "\($0.title) — \($0.blurb)" },
                            selection: $prefs.quality)
        }
        .sheet(isPresented: $showSponsorCategories) {
            MultiPickerSheet(title: "What to skip",
                             options: SponsorBlock.Category.allCases,
                             label: \.title, chosen: $prefs.sponsorCategories)
        }
        .sheet(isPresented: $showHistory) {
            ValuePickerSheet(title: "Keep history for",
                             options: PlaybackPrefs.historyOptions,
                             label: PlaybackPrefs.historyTitle,
                             selection: $prefs.historyDays)
        }
    }
}

/// Like `EnumPickerSheet`, for plain values that aren't `Identifiable`.
struct ValuePickerSheet<Value: Hashable>: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element) { i, option in
                        Button {
                            selection = option
                            dismiss()
                        } label: {
                            HStack {
                                Text(label(option))
                                    .font(.blaze(15))
                                    .foregroundStyle(palette.onSurface)
                                Spacer()
                                if option == selection {
                                    Image(systemName: "checkmark")
                                        .font(.blaze(13, .bold))
                                        .foregroundStyle(palette.accent)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < options.count - 1 {
                            Divider().overlay(palette.onSurface.opacity(0.06))
                        }
                    }
                }
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(16)
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

/// Several answers rather than one: the same list as `EnumPickerSheet`, but each
/// row toggles and the sheet stays open until it is closed, because choosing
/// three things one sheet at a time is nobody's idea of a setting.
struct MultiPickerSheet<Option: Identifiable>: View where Option.ID == String {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [Option]
    let label: (Option) -> String
    @Binding var chosen: Set<String>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { i, option in
                        Button {
                            if chosen.contains(option.id) {
                                chosen.remove(option.id)
                            } else {
                                chosen.insert(option.id)
                            }
                        } label: {
                            HStack {
                                Text(label(option))
                                    .font(.blaze(15))
                                    .foregroundStyle(palette.onSurface)
                                Spacer()
                                Image(systemName: chosen.contains(option.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.blaze(17))
                                    .foregroundStyle(chosen.contains(option.id)
                                                     ? palette.accent
                                                     : palette.onSurfaceVariant.opacity(0.5))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < options.count - 1 {
                            Divider().overlay(palette.onSurface.opacity(0.06))
                        }
                    }
                }
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(16)
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(palette.accent)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
