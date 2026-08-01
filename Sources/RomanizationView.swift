import SwiftUI

/// Settings → Lyrics → Romanization.
/// No library and no network needed: iOS transliterates with
/// `StringTransform.toLatin`, so it works offline and costs nothing.
struct RomanizationView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var prefs = RomanizePrefs.shared

    var body: some View {
        SettingsPage(title: "Romanization") {
            SettingsGroup(title: "Romanization") {
                SettingsToggle(symbol: "character", title: "Show romanised lyrics",
                               subtitle: "Write the sounds in Latin letters under each line",
                               isOn: $prefs.enabled)
                if prefs.enabled {
                    SettingsDivider()
                    SettingsToggle(symbol: "arrow.up.arrow.down",
                                   title: "Use it as the main line",
                                   subtitle: "Show the romanisation instead of the original script",
                                   isOn: $prefs.asMain)
                }
            }

            if prefs.enabled {
                SettingsGroup(title: "Scripts") {
                    ForEach(Array(Romanize.scripts.enumerated()), id: \.element.code) { i, script in
                        SettingsToggle(symbol: "textformat", title: script.name,
                                       isOn: Binding(
                                           get: { prefs.isOn(script.code) },
                                           set: { prefs.set(script.code, on: $0) }))
                        if i < Romanize.scripts.count - 1 { SettingsDivider() }
                    }
                }
            }

            Text("Romanisation happens on the phone — nothing is sent anywhere. "
                 + "It only appears for songs written in one of the scripts above; "
                 + "lyrics already in Latin letters are left alone. If AI "
                 + "translation is also on, romanisation wins, since stacking both "
                 + "under one line is unreadable.")
                .font(.blaze(12))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, 6)
        }
    }
}
