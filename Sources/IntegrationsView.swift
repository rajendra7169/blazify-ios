import SwiftUI

/// Settings → Integrations. Only Last.fm: Discord Rich Presence needs a socket
/// held open in the background, which iOS suspends, so it would only ever work
/// while you were staring at the app.
struct IntegrationsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var lastfm = LastFM.shared

    @State private var apiKey = ""
    @State private var secret = ""
    @State private var showKeys = false

    var body: some View {
        SettingsPage(title: "Integrations") {
            SettingsGroup(title: "Last.fm") {
                if lastfm.isConnected {
                    SettingsLink(symbol: "person.crop.circle.badge.checkmark",
                                 title: lastfm.username ?? "Connected",
                                 subtitle: "Tap to disconnect") { lastfm.disconnect() }
                    SettingsDivider()
                    SettingsToggle(symbol: "waveform.badge.magnifyingglass",
                                   title: "Scrobble",
                                   subtitle: "Send songs you play to your profile",
                                   isOn: $lastfm.scrobbling)
                    SettingsDivider()
                    SettingsToggle(symbol: "heart", title: "Love on favourite",
                                   subtitle: "Mark a song loved when you favourite it here",
                                   isOn: $lastfm.loveOnFavorite)
                } else {
                    SettingsLink(symbol: "key", title: "API key and secret",
                                 subtitle: lastfm.hasCredentials ? "Saved" : "Not set yet") {
                        showKeys = true
                    }
                    if lastfm.hasCredentials {
                        SettingsDivider()
                        SettingsLink(symbol: "arrow.up.forward.square",
                                     title: "Connect your account",
                                     subtitle: "Opens Last.fm to approve, then come back") {
                            Task {
                                if let url = await lastfm.requestToken() {
                                    await UIApplication.shared.open(url)
                                }
                            }
                        }
                        SettingsDivider()
                        SettingsLink(symbol: "checkmark.circle", title: "I've approved it",
                                     subtitle: "Finishes signing in") {
                            Task { await lastfm.completeAuth() }
                        }
                    }
                }
            }

            if let status = lastfm.status {
                Text(status)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 6)
            }

            Text("Blazify doesn't ship Last.fm credentials, so scrobbling uses "
                 + "yours. Create an API account at last.fm/api — it's free and "
                 + "takes a minute — then paste the key and shared secret above. "
                 + "They're kept in the iOS Keychain, never in a file.")
                .font(.system(size: 12))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, 6)

            Text("Discord Rich Presence isn't here: it needs a connection held "
                 + "open in the background, which iOS suspends, so it would only "
                 + "show while the app was on screen.")
                .font(.system(size: 12))
                .foregroundStyle(palette.onSurfaceVariant.opacity(0.8))
                .padding(.horizontal, 6)
        }
        .sheet(isPresented: $showKeys) {
            NavigationStack {
                Form {
                    Section("Last.fm API account") {
                        TextField("API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Shared secret", text: $secret)
                    }
                    .listRowBackground(palette.surface)
                }
                .scrollContentBackground(.hidden)
                .background(palette.scaffold.ignoresSafeArea())
                .navigationTitle("Credentials")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            lastfm.saveCredentials(key: apiKey, secret: secret)
                            apiKey = ""; secret = ""
                            showKeys = false
                        }
                        .tint(palette.accent)
                        .disabled(apiKey.isEmpty || secret.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
