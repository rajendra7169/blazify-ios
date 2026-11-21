import SwiftUI

/// Settings → Content. Proxy is left out: iOS
/// routes through the system's network settings, and a per-app proxy would only
/// cover our own requests while the OS keeps its own. Everything else here is
/// live — the language and region go into every request YouTube sees.
struct ContentSettingsView: View {
    @ObservedObject private var prefs = ContentPrefs.shared
    @State private var showLanguage = false
    @State private var showBlocked = false
    @ObservedObject private var blocked = BlockedArtists.shared
    @State private var showCountry = false

    var body: some View {
        SettingsPage(title: "Content") {
            SettingsGroup(title: "Region") {
                SettingsLink(symbol: "character.bubble", title: "Content language",
                             subtitle: ContentPrefs.name(ofLanguage: prefs.language)) {
                    showLanguage = true
                }
                SettingsDivider()
                SettingsLink(symbol: "globe", title: "Content region",
                             subtitle: ContentPrefs.name(ofCountry: prefs.country)) {
                    showCountry = true
                }
            }

            SettingsGroup(title: "Filters") {
                SettingsLink(symbol: "nosign", title: "Blocked artists",
                             subtitle: blocked.entries.isEmpty
                                 ? "No one is blocked"
                                 : "\(blocked.entries.count) blocked") {
                    showBlocked = true
                }
                SettingsDivider()
                SettingsToggle(symbol: "e.square", title: "Hide explicit",
                               subtitle: "Leave explicit songs out of results and feeds",
                               isOn: $prefs.hideExplicit)
                SettingsDivider()
                SettingsToggle(symbol: "video.slash", title: "Hide video songs",
                               subtitle: "Skip music videos and keep the audio versions",
                               isOn: $prefs.hideVideoSongs)
                SettingsDivider()
                SettingsToggle(symbol: "rectangle.portrait.slash", title: "Hide YouTube Shorts",
                               subtitle: "Drops Shorts shelves out of Home",
                               isOn: $prefs.hideShorts)
            }

            SettingsGroup(title: "Artist pages") {
                SettingsToggle(symbol: "text.alignleft", title: "Show the description",
                               isOn: $prefs.showArtistDescription)
                SettingsDivider()
                SettingsToggle(symbol: "person.badge.plus", title: "Show subscribers",
                               isOn: $prefs.showSubscriberCount)
            }

            SettingsGroup(title: "Home") {
                SettingsToggle(symbol: "shuffle", title: "Shuffle the section order",
                               subtitle: "Show the rails in a different order each refresh",
                               isOn: $prefs.randomizeHomeOrder)
                SettingsDivider()
                SettingsToggle(symbol: "chart.line.uptrend.xyaxis",
                               title: "Show your stats playlists",
                               subtitle: "Top songs and most-played rails on Home and Yours",
                               isOn: $prefs.showStatsPlaylists)
            }

            // With no connection, Home's For you and Speed dial play the songs
            // saved on the phone; each kind of saved song can be left out.
            SettingsGroup(title: "Home with no connection") {
                SettingsToggle(symbol: "arrow.clockwise.icloud", title: "Cached songs",
                               subtitle: "Songs kept whole in the song cache after you played them",
                               isOn: $prefs.offlineHomeCached)
                SettingsDivider()
                SettingsToggle(symbol: "arrow.down.circle", title: "Downloaded songs",
                               subtitle: "Songs you downloaded",
                               isOn: $prefs.offlineHomeDownloaded)
                SettingsDivider()
                SettingsToggle(symbol: "music.note.list", title: "Songs on this device",
                               subtitle: "Your own music files on this phone",
                               isOn: $prefs.offlineHomeDevice)
            }
        }
        .sheet(isPresented: $showLanguage) {
            ValuePickerSheet(title: "Content language",
                             options: ContentPrefs.languages.map(\.code),
                             label: ContentPrefs.name(ofLanguage:),
                             selection: $prefs.language)
        }
        .sheet(isPresented: $showCountry) {
            ValuePickerSheet(title: "Content region",
                             options: ContentPrefs.countries.map(\.code),
                             label: ContentPrefs.name(ofCountry:),
                             selection: $prefs.country)
        }
        .sheet(isPresented: $showBlocked) {
            NavigationStack { BlockedArtistsView() }
        }
    }
}
