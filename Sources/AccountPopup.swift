import SwiftUI
import UIKit

/// The account popup from the home header: a card in the middle of the
/// screen (16pt sides, 28pt radius) over a dimmed tap-to-dismiss backdrop.
struct AccountPopup: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @Binding var isPresented: Bool

    @ObservedObject private var auth = Auth.shared

    @State private var showLogin = false
    @State private var showAccount = false
    @State private var tokenText = ""
    @State private var showTokenSheet = false
    @State private var confirmLogout = false
    @State private var showTogether = false
    @State private var showDeveloper = false
    /// The accounts list under the card's arrow.
    @State private var expanded = false
    @State private var channels: [YouTube.AccountChannel] = []
    @State private var loadingChannels = false
    @State private var channelsLoaded = false
    @State private var switching = false
    @State private var switchFailed = false
    @State private var confirmRemove: SavedAccount?
    @State private var moreContent = UserDefaults.standard.object(forKey: "useLoginForBrowse") as? Bool ?? true
    @State private var autoSync = UserDefaults.standard.object(forKey: "ytmSync") as? Bool ?? true

    var body: some View {
        ZStack {
            // The backdrop takes every tap that doesn't land on the card.
            // It couldn't before: the card lived in a scroll view that filled
            // the screen, so there was nowhere left for an outside tap to go
            // and the cross was the only way out.
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }

            // As tall as what is in it, and centred, as Android's dialog is.
            // Only on a screen too short to hold it does it scroll — a card
            // given a fixed height was 560pt of panel with a scroll bar in it.
            ViewThatFits(in: .vertical) {
                card
                ScrollView { card }
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)

            // The developer, in a small card over this one — as on Android,
            // where it is a dialog — rather than a page of its own.
            if showDeveloper {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { showDeveloper = false }
                    .transition(.opacity)
                developerCard
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: showDeveloper)
        // Adding starts from an empty sign-in page; otherwise Google sees the
        // account already in use and hands it straight back.
        .sheet(isPresented: $showLogin) { LoginView(freshStart: true) }
        .sheet(isPresented: $showAccount) { AccountLibraryView(player: player) }
        .sheet(isPresented: $showTokenSheet) { tokenSheet }
        .sheet(isPresented: $showTogether) { TogetherView() }
        .confirmationDialog("Keep library data?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) {
                auth.signOut()
                isPresented = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloaded songs are always kept.")
        }
        // Removing is asked about first: it sits one tap from switching, and
        // getting the account back means signing in to it again.
        .alert(
            "Remove \(confirmRemove?.name ?? "this account") from this phone?",
            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })
        ) {
            Button("Remove", role: .destructive) {
                if let account = confirmRemove { auth.forget(account) }
                confirmRemove = nil
            }
            Button("Cancel", role: .cancel) { confirmRemove = nil }
        } message: {
            Text("To use this account here again, you will need to sign in to it again. Nothing changes on the Google account itself.")
        }
        .alert("Couldn't switch account", isPresented: $switchFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That account didn't answer. It may have been signed out: check your connection, or remove it and add it again.")
        }
        // A session from before there was a list joins it the first time
        // this opens, so it can be switched back to.
        .onAppear { auth.rememberCurrent() }
    }

    private var card: some View {
        VStack(spacing: 0) {
            titleBar
            accountCard
            Spacer().frame(height: 8)
            toggleGroup
            Spacer().frame(height: 12)
            developerRow
            Spacer().frame(height: 12)
            bottomBlock
        }
        .padding(16)
    }

    /// "Know about the developer", as Android heads it: the photo, who it is,
    /// and a tap for the rest.
    private var developerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Know about the developer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            Button { showDeveloper = true } label: {
                HStack(spacing: 12) {
                    Image("DeveloperPhoto")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rajendra Pandey")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.onSurface)
                        Text("Developer, Kathmandu")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(palette.onSurface.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// Android's dialog, line for line: photo, name, what he does, a few words
    /// in his own voice, and the two places to find him.
    private var developerCard: some View {
        VStack(spacing: 0) {
            Image("DeveloperPhoto")
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())

            Spacer().frame(height: 12)
            Text("Rajendra Pandey")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.onSurface)
            Spacer().frame(height: 2)
            Text("Builds Blazify, from Kathmandu")
                .font(.system(size: 13))
                .foregroundStyle(palette.onSurfaceVariant)

            Spacer().frame(height: 14)
            Text("I build Blazify on my own, in the open. It began because I wanted a music player that looked the way I thought one should, and people kept asking me for a copy. What goes into each version is mostly what people tell me is broken or missing.")
                .font(.system(size: 14))
                .foregroundStyle(palette.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)

            Spacer().frame(height: 16)
            HStack(spacing: 8) {
                developerLink("Website", "https://rajendrapandey.info.np")
                developerLink("GitHub", "https://github.com/rajendra7169")
            }
            Spacer().frame(height: 4)
        }
        .padding(24)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .padding(.horizontal, 36)
    }

    private func developerLink(_ label: String, _ address: String) -> some View {
        Button {
            if let url = URL(string: address) { UIApplication.shared.open(url) }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var titleBar: some View {
        HStack {
            // The name in the Blaze gradient, which is what Android paints here
            // and what makes this a Blazify panel rather than a settings card.
            Text("Blazify")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [Blaze.amber, Blaze.orange],
                                   startPoint: .leading, endPoint: .trailing),
                )
                .padding(.leading, 4)
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .frame(width: 36, height: 36)
                    // Sitting in its own round well, as it does on Android —
                    // a bare glyph in a corner reads as decoration.
                    .background(Circle().fill(palette.onSurface.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }

    // MARK: Account card

    /// Who is signed in, and every other account on this phone one tap away
    /// beneath it.
    ///
    /// The photo carries a small "+1" when other accounts are saved, so it is
    /// plain there is somewhere to switch to. The arrow opens the list in
    /// place: the channels of this account, the other accounts, a row to add
    /// another, and Log out last. Signed out, the card offers to add an
    /// account, and still lists any saved ones to go back to.
    private var accountCard: some View {
        let others = auth.otherAccounts.count
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    if auth.isLoggedIn { showAccount = true } else { showLogin = true }
                } label: {
                    HStack(spacing: 12) {
                        cardPhoto()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.isLoggedIn ? (auth.accountName ?? "Account") : "Add an account")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(palette.onSurface)
                                .lineLimit(1)
                            Text(cardSubtitle(others: others))
                                .font(.system(size: 13))
                                .foregroundStyle(palette.onSurfaceVariant)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if auth.isLoggedIn || others > 0 {
                    // The list is read before it opens, with the arrow turning into a
                    // spinner meanwhile, so it opens complete instead of jumping.
                    Button {
                        if expanded {
                            withAnimation(.easeOut(duration: 0.2)) { expanded = false }
                        } else if !loadingChannels {
                            loadChannels {
                                withAnimation(.easeOut(duration: 0.2)) { expanded = true }
                            }
                        }
                    } label: {
                        Group {
                            if loadingChannels {
                                ProgressView()
                                    .tint(palette.accent)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.onSurface)
                                    .rotationEffect(.degrees(expanded ? 180 : 0))
                            }
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accounts and channels")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 12)

            if expanded {
                accountsPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(palette.onSurface.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func cardSubtitle(others: Int) -> String {
        if others == 1 { return "1 more account" }
        if others > 1 { return "\(others) more accounts" }
        if auth.isLoggedIn { return auth.accountEmail ?? "Your account, channels and sync" }
        return "Sign in with Google for your playlists and library"
    }

    /// The face of the account in use, or a plus when there is none. How many
    /// other accounts are saved is said in the line under the name.
    private func cardPhoto() -> some View {
        ZStack {
            if auth.isLoggedIn {
                accountPhoto(auth.accountPhoto, size: 44)
            } else {
                Circle()
                    .fill(palette.accent.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.accent),
                    )
            }
        }
    }

    @ViewBuilder
    private func accountPhoto(_ photo: String?, size: CGFloat) -> some View {
        if let photo, let url = URL(string: photo) {
            RemoteImage(url: url, size: size, logo: false) { Circle().fill(palette.heroGradient) }
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle().fill(palette.heroGradient)
                .frame(width: size, height: size)
                .overlay(Image(systemName: "person.fill").foregroundStyle(palette.onSurface))
        }
    }

    /// The list under the arrow.
    private var accountsPanel: some View {
        let active = activeChannel
        // A channel of this account saved from an earlier switch is already
        // in the channel list; once is enough.
        let others = auth.otherAccounts.filter { account in
            !channels.contains(where: { $0.id == account.dataSyncId && $0.name == account.name })
        }
        return VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(palette.onSurface.opacity(0.10))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            // One line for somebody with one channel would only repeat the card.
            if channels.count > 1 {
                panelHeading("Channels on this account")
                ForEach(channels) { channel in
                    accountRow(name: channel.name, detail: channel.handle, photo: channel.photo,
                               selected: channel.id == active?.id,
                               onTap: { if channel.id != active?.id { switchToChannel(channel) } })
                }
            }

            if !others.isEmpty {
                panelHeading("Other accounts")
                ForEach(others) { account in
                    accountRow(name: account.name.isEmpty ? (account.email ?? "Account") : account.name,
                               detail: account.email, photo: account.photo, selected: false,
                               onTap: { switchTo(account) },
                               onRemove: { confirmRemove = account })
                }
            }

            Button { showLogin = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 40, height: 40)
                    Text("Add another account")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.onSurface)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(switching)

            if switching {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(palette.accent)
                        .frame(width: 40, height: 40)
                    Text("Switching…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Inside the list rather than beside the name, where a button left
            // room for only the first few letters of it.
            if auth.isLoggedIn {
                Button { confirmLogout = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(logoutRed)
                            .frame(width: 40, height: 40)
                        Text("Log out")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(logoutRed)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(switching)
            }
        }
        .padding(.bottom, 8)
    }

    private var logoutRed: Color { Color(hex: 0xE53935) }

    private func panelHeading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func accountRow(name: String, detail: String?, photo: String?, selected: Bool,
                            onTap: @escaping () -> Void, onRemove: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    accountPhoto(photo, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                            .lineLimit(1)
                        if let detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.onSurfaceVariant)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(switching)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(switching)
                .accessibilityLabel("Remove from this phone")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// The channel in use: the one this phone was told to use, or else
    /// whichever the answer marks.
    private var activeChannel: YouTube.AccountChannel? {
        if let named = channels.first(where: { $0.id == auth.dataSyncId }) { return named }
        if let marked = channels.first(where: { $0.isSelected }) { return marked }
        return channels.first
    }

    // MARK: Switching

    /// Asked the first time the list is opened, never longer than 12 seconds;
    /// `then` runs once the channels are in, or straight away when there is
    /// nothing to ask.
    private func loadChannels(then: @escaping () -> Void = {}) {
        guard auth.isLoggedIn, !channelsLoaded, !loadingChannels else { then(); return }
        loadingChannels = true
        Task {
            let found = await withTimeLimit(seconds: 12) { () async -> [YouTube.AccountChannel]? in
                await YouTube.accountChannels()
            } ?? []
            await MainActor.run {
                channels = found
                channelsLoaded = true
                loadingChannels = false
                then()
            }
        }
    }

    /// Make another saved account the one in use. Home and Library reload as
    /// it underneath, so the panel closes once it has; one that no longer
    /// answers changes nothing and says so.
    private func switchTo(_ account: SavedAccount) {
        guard !switching else { return }
        switching = true
        Task {
            let ok = await auth.use(account)
            await MainActor.run {
                switching = false
                if ok {
                    channels = []
                    channelsLoaded = false
                    expanded = false
                    isPresented = false
                } else {
                    switchFailed = true
                }
            }
        }
    }

    /// Another channel of the same Google account: the same sign-in, made on
    /// behalf of a different channel.
    private func switchToChannel(_ channel: YouTube.AccountChannel) {
        let saved = auth.savedAccounts.first(where: { $0.id == auth.currentAccountKey })
        var target = saved ?? SavedAccount(cookie: auth.cookie ?? "", visitorData: auth.visitorData,
                                           dataSyncId: auth.dataSyncId, name: auth.accountName ?? "",
                                           email: auth.accountEmail, photo: auth.accountPhoto)
        guard !target.cookie.isEmpty else { return }
        target.dataSyncId = channel.id
        target.name = channel.name
        target.photo = channel.photo
        switchTo(target)
    }

    // MARK: Token + toggles

    private var toggleGroup: some View {
        VStack(spacing: 4) {
            Button { tapToken() } label: {
                row(icon: "key", title: tokenTitle, corners: (24, 6))
            }
            .buttonStyle(.plain)

            toggleRow(icon: "arrow.triangle.2.circlepath", title: "More content",
                      isOn: $moreContent, key: "useLoginForBrowse", corners: (6, 6))

            toggleRow(icon: "arrow.triangle.2.circlepath", title: "Auto-sync with account",
                      isOn: $autoSync, key: "ytmSync", corners: (6, 24))
        }
    }

    private var tokenTitle: String {
        auth.isLoggedIn ? "Tap to show token" : "Log in with token"
    }

    /// One tap opens it. The old two-tap reveal changed only this row's label
    /// on the first tap, which just looked like nothing had happened.
    private func tapToken() {
        tokenText = auth.tokenBlob()
        showTokenSheet = true
    }

    private var tokenSheet: some View {
        NavigationStack {
            ScrollView {
                Text(tokenText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.onSurface)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(palette.surface.ignoresSafeArea())
            .navigationTitle("Account token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") { UIPasteboard.general.string = tokenText }.tint(palette.accent)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showTokenSheet = false }.tint(palette.accent)
                }
            }
        }
    }

    // MARK: Bottom block

    private var bottomBlock: some View {
        VStack(spacing: 4) {
            Button { showTogether = true } label: {
                row(icon: "person.2", title: "Blaze Together", corners: (16, 6))
            }
            .buttonStyle(.plain)

            Button {
                isPresented = false
                NotificationCenter.default.post(name: .openBlazifySettings, object: nil)
            } label: {
                row(icon: "gearshape", title: "Settings", corners: (16, 16))
            }
            .buttonStyle(.plain)
        }
        .background(palette.onSurface.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Bits

    private func row(icon: String, title: String, corners: (CGFloat, CGFloat)) -> some View {
        HStack(spacing: 16) {
            iconChip(icon)
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.onSurface)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>,
                           key: String, corners: (CGFloat, CGFloat)) -> some View {
        HStack(spacing: 16) {
            iconChip(icon)
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(auth.isLoggedIn ? palette.onSurface : palette.onSurface.opacity(0.35))
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(palette.accent)
                .disabled(!auth.isLoggedIn)
                .onChange(of: isOn.wrappedValue) {
                    UserDefaults.standard.set(isOn.wrappedValue, forKey: key)
                }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(palette.onSurface.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func iconChip(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 18))
            .foregroundStyle(palette.accent)
            .frame(width: 40, height: 40)
            .background(palette.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension Notification.Name {
    static let openBlazifySettings = Notification.Name("openBlazifySettings")
}
