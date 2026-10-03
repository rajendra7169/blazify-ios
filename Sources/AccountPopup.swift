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
        .sheet(isPresented: $showLogin) { LoginView() }
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

    private var accountCard: some View {
        Button {
            if auth.isLoggedIn { showAccount = true } else { showLogin = true }
        } label: {
            HStack(spacing: 12) {
                if auth.isLoggedIn {
                    // Whoever is signed in, shown as themselves.
                    if let photo = auth.accountPhoto, let url = URL(string: photo) {
                        RemoteImage(url: url, size: 40) { Circle().fill(palette.heroGradient) }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        Circle().fill(palette.heroGradient)
                            .frame(width: 40, height: 40)
                            .overlay(Image(systemName: "person.fill").foregroundStyle(palette.onSurface))
                    }
                } else {
                    iconChip("rectangle.portrait.and.arrow.right")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.isLoggedIn ? (auth.accountName ?? "Account") : "Login")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.onSurface).lineLimit(1)
                    if let email = auth.accountEmail, auth.isLoggedIn {
                        Text(email)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)

                if auth.isLoggedIn {
                    Button { confirmLogout = true } label: {
                        Text("Log out")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .overlay(Capsule().stroke(palette.onSurface.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .background(palette.onSurface.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
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
