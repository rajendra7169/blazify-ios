import SwiftUI

/// Settings, ported from SettingsScreen.kt: profile header, a search field that
/// filters the top-level rows, quick toggles for theme mode / dynamic / pure
/// black, then the grouped sections.
struct SettingsView: View {
    @ObservedObject var player: Player
    @ObservedObject private var auth = Auth.shared
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var showLogin = false
    @State private var showAccount = false
    @State private var showDownloads = false

    private struct Row: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        var action: Action = .none
        enum Action { case none, account, downloads }
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
                    subtitle: "Preview and style theme and mini-player"),
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
                Row(icon: "person.2", title: "Together",
                    subtitle: "Listen Together sync and room settings"),
            ]),
            Group(title: "Privacy & data", rows: [
                Row(icon: "lock", title: "Privacy", subtitle: "History, pauses, listening data"),
                Row(icon: "internaldrive", title: "Storage",
                    subtitle: "Cache, downloads, clear data", action: .downloads),
                Row(icon: "arrow.clockwise", title: "Backup and restore",
                    subtitle: "Export or import your library"),
            ]),
            Group(title: "About", rows: [
                Row(icon: "info.circle", title: "About", subtitle: "Version and developer"),
                Row(icon: "newspaper", title: "Changelog", subtitle: "What's new in this version"),
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
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.leading, 6)
                            Spacer()
                        }
                        .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { i, row in
                                settingRow(row, index: i)
                                if i < group.rows.count - 1 {
                                    Divider().overlay(Color.white.opacity(0.08))
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(theme.scaffold.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Blaze.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLogin) { LoginView() }
        .sheet(isPresented: $showAccount) { AccountLibraryView(player: player) }
        .sheet(isPresented: $showDownloads) { DownloadsView(player: player) }
    }

    // MARK: Header

    private var profileHeader: some View {
        Button {
            if auth.isLoggedIn { showAccount = true } else { showLogin = true }
        } label: {
            HStack(spacing: 14) {
                Circle().fill(Blaze.amber)
                    .frame(width: 46, height: 46)
                    .overlay(Image(systemName: "person.fill")
                        .font(.system(size: 22)).foregroundStyle(.black))
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.accountName ?? "Guest")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(auth.isLoggedIn ? "Manage your account" : "Tap to sign in")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Blaze.amber.opacity(0.18), Blaze.amber.opacity(0.06)],
                               startPoint: .leading, endPoint: .trailing),
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
            TextField("Search settings", text: $query)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(Blaze.amber)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }

    // MARK: Quick toggles

    private var quickToggles: some View {
        HStack(spacing: 8) {
            quickChip(icon: "moon.stars", label: "Dark", active: true) {}
            quickChip(icon: "paintpalette", label: "Dynamic", active: theme.dynamicTheme) {
                theme.setDynamicTheme(!theme.dynamicTheme)
            }
            quickChip(icon: "circle.fill", label: "Pure black", active: theme.pureBlack) {
                theme.setPureBlack(!theme.pureBlack)
            }
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
            .foregroundStyle(active ? Blaze.amber : .white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12).padding(.horizontal, 8)
            .background(active ? Blaze.amber.opacity(0.18) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(active ? Blaze.amber : .clear, lineWidth: 1.5),
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Rows

    private func settingRow(_ row: Row, index: Int) -> some View {
        // Icon chips cycle through three accents by row index, as on Android.
        let tints: [Color] = [Blaze.amber, Blaze.orange, player.artColor]
        let tint = tints[index % 3]
        let live = row.action != .none

        return Button {
            switch row.action {
            case .account: showAccount = true
            case .downloads: showDownloads = true
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
                        .foregroundStyle(.white).lineLimit(1)
                    Text(live ? row.subtitle : row.subtitle + " · coming soon")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
            .opacity(live ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!live)
    }
}
