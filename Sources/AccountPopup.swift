import SwiftUI
import UIKit

/// The account popup from the home header, ported from AccountSettings.kt: a
/// card pinned near the top (72pt down, 16pt sides, 28pt radius) over a dimmed
/// tap-to-dismiss backdrop.
struct AccountPopup: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @Binding var isPresented: Bool

    @ObservedObject private var auth = Auth.shared
    @ObservedObject private var theme = AppTheme.shared

    @State private var showLogin = false
    @State private var showAccount = false
    @State private var showToken = false
    @State private var tokenText = ""
    @State private var showTokenSheet = false
    @State private var confirmLogout = false
    @State private var showTogether = false
    @State private var moreContent = UserDefaults.standard.object(forKey: "useLoginForBrowse") as? Bool ?? true
    @State private var autoSync = UserDefaults.standard.object(forKey: "ytmSync") as? Bool ?? true

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            ScrollView {
                VStack(spacing: 0) {
                    titleBar
                    accountCard
                    Spacer().frame(height: 8)
                    toggleGroup
                    Spacer().frame(height: 12)
                    bottomBlock
                }
                .padding(16)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 72)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(.dark)
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

    private var titleBar: some View {
        HStack {
            Text("Blazify")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.leading, 4)
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: Account card

    private var accountCard: some View {
        Button {
            if auth.isLoggedIn { showAccount = true } else { showLogin = true }
        } label: {
            HStack(spacing: 12) {
                if auth.isLoggedIn {
                    Circle().fill(palette.heroGradient)
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "person.fill").foregroundStyle(palette.onSurface))
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
                            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
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
        if !auth.isLoggedIn { return "Log in with token" }
        return showToken ? "Tap again to copy or edit" : "Tap to show token"
    }

    /// Two-tap reveal, as on Android: first tap unhides, second opens the editor.
    private func tapToken() {
        if !auth.isLoggedIn || showToken {
            tokenText = auth.tokenBlob()
            showTokenSheet = true
        } else {
            showToken = true
        }
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
            .background(theme.surface.ignoresSafeArea())
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
        .preferredColorScheme(.dark)
    }

    // MARK: Bottom block

    private var bottomBlock: some View {
        VStack(spacing: 4) {
            Button { showTogether = true } label: {
                row(icon: "person.2", title: "Together", corners: (16, 6))
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
                .foregroundStyle(auth.isLoggedIn ? .white : .white.opacity(0.4))
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
