import SwiftUI

/// Settings, ported from SettingsScreen.kt: profile header, a search field that
/// filters the top-level rows, quick toggles for theme mode / dynamic / pure
/// black, then the grouped sections.
struct SettingsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var auth = Auth.shared
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var showLogin = false
    @State private var showAccount = false
    @State private var showDownloads = false
    @State private var showStorage = false
    @State private var showAbout = false
    @State private var showLookFeel = false
    @State private var showTogether = false
    @State private var showPrivacy = false
    @State private var showChangelog = false

    private struct Row: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        var action: Action = .none
        enum Action { case none, account, downloads, storage, about, lookFeel, together, privacy, changelog }
    }

    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let rows: [Row]
    }

    private var groups: [Group] {
        [
            Group(title: "Personalize", rows: [
                Row(icon: "paintbrush", title: "Appearance",
                    subtitle: "Theme, colors, dark mode, layout"),
                Row(icon: "rectangle.on.rectangle", title: "Look & Feel",
                    subtitle: "Preview and style theme, player, mini-player and home",
                    action: .lookFeel),
            ]),
            Group(title: "Playback", rows: [
                Row(icon: "play.circle", title: "Player and audio",
                    subtitle: "Quality, crossfade, sleep timer, queue"),
                Row(icon: "antenna.radiowaves.left.and.right", title: "Stream sources",
                    subtitle: "Where audio is fetched from"),
            ]),
            Group(title: "Content", rows: [
                Row(icon: "globe", title: "Content", subtitle: "Region, explicit, video songs"),
                Row(icon: "quote.bubble", title: "Lyrics",
                    subtitle: "Sources, sync, translation, display"),
            ]),
            Group(title: "Connections", rows: [
                Row(icon: "link", title: "Integrations",
                    subtitle: "Discord Rich Presence, Last.fm scrobbling"),
                Row(icon: "person.2", title: "Blaze Together",
                    subtitle: "Username, server, auto-approve, blocked users, logs",
                    action: .together),
            ]),
            Group(title: "Privacy & data", rows: [
                Row(icon: "lock", title: "Privacy", subtitle: "Pause or clear listen and search history",
                    action: .privacy),
                Row(icon: "internaldrive", title: "Storage",
                    subtitle: "Cache, downloads, clear data", action: .storage),
                Row(icon: "arrow.clockwise", title: "Backup and restore",
                    subtitle: "Export or import your library"),
            ]),
            Group(title: "About", rows: [
                Row(icon: "info.circle", title: "About", subtitle: "Version and developer", action: .about),
                Row(icon: "newspaper", title: "Changelog", subtitle: "What's new in each release",
                    action: .changelog),
            ]),
        ]
    }

    private var filtered: [Group] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return groups }
        return groups.compactMap { group in
            let rows = group.rows.filter {
                $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
            }
            return rows.isEmpty ? nil : Group(title: group.title, rows: rows)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    Spacer().frame(height: 12)
                    searchField
                    if query.isEmpty {
                        Spacer().frame(height: 12)
                        quickToggles
                    }

                    ForEach(filtered) { group in
                        Spacer().frame(height: 18)
                        HStack {
                            Text(group.title.uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(palette.onSurfaceVariant)
                                .padding(.leading, 6)
                            Spacer()
                        }
                        .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { i, row in
                                settingRow(row, index: i)
                                if i < group.rows.count - 1 {
                                    Divider().overlay(palette.onSurface.opacity(0.06))
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(palette.accent)
                }
            }
        }
        // A sheet is its own presentation: the root's colour scheme and palette
        // don't reliably follow it in. Without these, changing Light/Dark from
        // inside Settings looks like it did nothing at all.
        .preferredColorScheme(theme.preferredColorScheme)
        .environment(\.palette, Palette(dark: theme.resolvedDark))
        .sheet(isPresented: $showLogin) { LoginView() }
        .sheet(isPresented: $showAccount) { AccountLibraryView(player: player) }
        .sheet(isPresented: $showDownloads) { DownloadsView(player: player) }
        .sheet(isPresented: $showStorage) {
            NavigationStack { StorageSettingsView() }
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
        .sheet(isPresented: $showAbout) {
            NavigationStack { AboutView() }
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack { PrivacyView() }
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
        .sheet(isPresented: $showChangelog) {
            ChangelogView()
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
        .sheet(isPresented: $showTogether) {
            NavigationStack { TogetherSettingsView() }
                .preferredColorScheme(theme.preferredColorScheme)
                .environment(\.palette, Palette(dark: theme.resolvedDark))
        }
        .fullScreenCover(isPresented: $showLookFeel) {
            NavigationStack {
                LookAndFeelView(player: player)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showLookFeel = false }
                        }
                    }
            }
            .preferredColorScheme(theme.preferredColorScheme)
        }
    }

    // MARK: Header

    private var profileHeader: some View {
        Button {
            if auth.isLoggedIn { showAccount = true } else { showLogin = true }
        } label: {
            HStack(spacing: 14) {
                Circle().fill(palette.accent)
                    .frame(width: 46, height: 46)
                    .overlay(Image(systemName: "person.fill")
                        .font(.system(size: 22)).foregroundStyle(.black))
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.accountName ?? "Guest")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.onSurface).lineLimit(1)
                    Text(auth.isLoggedIn ? "Manage your account" : "Tap to sign in")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14)).foregroundStyle(palette.onSurfaceVariant)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [palette.accent.opacity(0.18), palette.accent.opacity(0.06)],
                               startPoint: .leading, endPoint: .trailing),
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16)).foregroundStyle(palette.onSurfaceVariant)
            TextField("Search settings", text: $query)
                .font(.system(size: 15))
                .foregroundStyle(palette.onSurface)
                .tint(palette.accent)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.onSurface.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(palette.onSurface.opacity(0.06))
        .clipShape(Capsule())
    }

    // MARK: Quick toggles

    private var quickToggles: some View {
        HStack(spacing: 8) {
            quickChip(icon: themeModeIcon, label: theme.darkMode.title,
                      active: theme.darkMode != .auto) { cycleDarkMode() }
            quickChip(icon: "paintpalette", label: "Dynamic", active: theme.dynamicTheme) {
                theme.setDynamicTheme(!theme.dynamicTheme)
            }
            quickChip(icon: "circle.fill", label: "Pure black", active: theme.pureBlack) {
                theme.setPureBlack(!theme.pureBlack)
            }
        }
    }

    private var themeModeIcon: String {
        switch theme.darkMode {
        case .auto: "circle.lefthalf.filled"
        case .on: "moon.stars"
        case .off: "sun.max"
        }
    }

    /// Auto -> Dark -> Light, as the Android quick toggle does.
    private func cycleDarkMode() {
        switch theme.darkMode {
        case .auto: theme.setDarkMode(.on)
        case .on: theme.setDarkMode(.off)
        case .off: theme.setDarkMode(.auto)
        }
    }

    private func quickChip(icon: String, label: String, active: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 11, weight: active ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? palette.accent : palette.onSurfaceVariant)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12).padding(.horizontal, 8)
            .background(active ? palette.accent.opacity(0.18) : palette.onSurface.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(active ? palette.accent : .clear, lineWidth: 1.5),
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Rows

    private func settingRow(_ row: Row, index: Int) -> some View {
        // Icon chips cycle through three shades, all derived from the live
        // accent, so they follow the album-art colour instead of sitting on a
        // fixed orange.
        let tints: [Color] = [
            palette.accent,
            palette.accent.tone(palette.dark ? 72 : 46, chroma: 0.72),
            palette.accent.tone(palette.dark ? 88 : 34, chroma: 0.5),
        ]
        let tint = tints[index % 3]
        let live = row.action != .none

        return Button {
            switch row.action {
            case .account: showAccount = true
            case .downloads: showDownloads = true
            case .storage: showStorage = true
            case .about: showAbout = true
            case .lookFeel: showLookFeel = true
            case .together: showTogether = true
            case .privacy: showPrivacy = true
            case .changelog: showChangelog = true
            case .none: break
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: row.icon)
                    .font(.system(size: 19))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.onSurface).lineLimit(1)
                    Text(live ? row.subtitle : row.subtitle + " · coming soon")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13)).foregroundStyle(palette.onSurface.opacity(0.35))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
            .opacity(live ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!live)
    }
}
