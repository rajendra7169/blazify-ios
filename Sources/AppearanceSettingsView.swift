import SwiftUI

/// Settings → Appearance. Theme, palette, player, mini-player and nav-bar styles
/// all live in the Look & Feel hub, where you can see them change — repeating
/// them here would mean two places to set one thing. What's left is everything
/// Look & Feel doesn't preview.
///
/// Options with no honest iOS counterpart are omitted rather than shown
/// dead: display density and high refresh rate are decided by iOS, landscape
/// scaling is handled by the layout itself, and the dynamic launcher icon needs
/// alternate icons declared at build time.
struct AppearanceSettingsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var look = LookFeel.shared
    @State private var showDefaultTab = false
    @State private var showGridSize = false

    var body: some View {
        SettingsPage(title: "Appearance") {
            SettingsGroup(title: "Layout") {
                SettingsLink(symbol: "square.grid.2x2", title: "Open on",
                             subtitle: look.defaultTab.title) { showDefaultTab = true }
                SettingsDivider()
                SettingsLink(symbol: "rectangle.grid.2x2", title: "Card size",
                             subtitle: look.gridItemSize.title) { showGridSize = true }
                SettingsDivider()
                SettingsToggle(symbol: "arrow.up.and.down.circle", title: "Slim navigation bar",
                               subtitle: "A shorter bar with icons only",
                               isOn: $look.slimNavBar)
            }

            SettingsGroup(title: "Home") {
                SettingsToggle(symbol: "sun.horizon", title: "Greeting card",
                               subtitle: "The good-morning card at the top of Home",
                               isOn: $look.showHomeGreeting)
                SettingsDivider()
                SettingsToggle(symbol: "magnifyingglass", title: "Search bar",
                               subtitle: "The search pill under the greeting",
                               isOn: $look.showHomeSearchBar)
            }

            SettingsGroup(title: "Player") {
                SettingsToggle(symbol: "hand.draw", title: "Swipe artwork to change song",
                               subtitle: "Swipe the album art left or right to skip",
                               isOn: $look.swipeThumbnail)
                SettingsDivider()
                SettingsToggle(symbol: "crop", title: "Fill the artwork frame",
                               subtitle: "Crop the art to a square instead of letterboxing it",
                               isOn: $look.cropAlbumArt)
                SettingsDivider()
                SettingsToggle(symbol: "eye.slash", title: "Hide the artwork",
                               subtitle: "A plain background with no album art in the player",
                               isOn: $look.hidePlayerThumbnail)
            }

            Text("Theme, colours, player and mini-player designs, slider style "
                 + "and the navigation bar are in Look & Feel, where you can see "
                 + "each change on a preview before you keep it.")
                .font(.blaze(12))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, 6)
        }
        .sheet(isPresented: $showDefaultTab) {
            EnumPickerSheet(title: "Open on", options: DefaultTab.allCases,
                            label: \.title, selection: $look.defaultTab)
        }
        .sheet(isPresented: $showGridSize) {
            EnumPickerSheet(title: "Card size", options: GridItemSize.allCases,
                            label: \.title, selection: $look.gridItemSize)
        }
    }
}
