import SwiftUI

/// Settings → Integrations: Last.fm and ListenBrainz. Discord Rich Presence
/// needs a socket held open in the background, which iOS suspends, so it would
/// only ever work while you were staring at the app.
struct IntegrationsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var lastfm = LastFM.shared
    @ObservedObject private var listenBrainz = ListenBrainz.shared

    @State private var apiKey = ""
    @State private var secret = ""
    @State private var showKeys = false
    @State private var showToken = false
    @State private var token = ""

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

            SettingsGroup(title: "ListenBrainz") {
                if listenBrainz.isConnected {
                    SettingsLink(symbol: "person.crop.circle.badge.checkmark",
                                 title: listenBrainz.username ?? "Connected",
                                 subtitle: "Tap to forget this token") {
                        listenBrainz.forget()
                    }
                    SettingsDivider()
                    SettingsToggle(symbol: "waveform.badge.magnifyingglass",
                                   title: "Send my listens",
                                   subtitle: "An open listening history you own and can take with you",
                                   isOn: $listenBrainz.scrobbling)
                } else {
                    SettingsLink(symbol: "key", title: "User token",
                                 subtitle: listenBrainz.checking ? "Checking the token…" : "Not set yet") {
                        showToken = true
                    }
                    SettingsDivider()
                    SettingsLink(symbol: "arrow.up.forward.square", title: "Get a token",
                                 subtitle: "Opens your ListenBrainz settings page") {
                        if let url = URL(string: "https://listenbrainz.org/settings/") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }

            if let status = listenBrainz.status {
                Text(status)
                    .font(.blaze(13, .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 6)
            }

            if let status = lastfm.status {
                Text(status)
                    .font(.blaze(13, .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 6)
            }

            Text("Blazify doesn't ship Last.fm credentials, so scrobbling uses "
                 + "yours. Create an API account at last.fm/api — it's free and "
                 + "takes a minute — then paste the key and shared secret above. "
                 + "They're kept in the iOS Keychain, never in a file.")
                .font(.blaze(12))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, 6)

            Text("ListenBrainz asks for nothing but the user token from its own "
                 + "settings page. It is kept in the Keychain, and forgetting it "
                 + "stops anything being sent from this phone.")
                .font(.blaze(12))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, 6)

            Text("Discord Rich Presence isn't here: it needs a connection held "
                 + "open in the background, which iOS suspends, so it would only "
                 + "show while the app was on screen.")
                .font(.blaze(12))
                .foregroundStyle(palette.onSurfaceVariant.opacity(0.8))
                .padding(.horizontal, 6)
        }
        .sheet(isPresented: $showToken) {
            NavigationStack {
                Form {
                    Section("ListenBrainz") {
                        SecureField("User token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .listRowBackground(palette.surface)
                    Section {
                        Text("Copy the user token from your ListenBrainz settings "
                             + "page and paste it here. It is checked before "
                             + "anything is sent.")
                            .font(.blaze(12))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                    .listRowBackground(palette.surface)
                }
                .scrollContentBackground(.hidden)
                .background(palette.scaffold.ignoresSafeArea())
                .navigationTitle("User token")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Check and save") {
                            let typed = token
                            token = ""
                            showToken = false
                            Task { await listenBrainz.connect(token: typed) }
                        }
                        .tint(palette.accent)
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
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
