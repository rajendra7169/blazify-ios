import SwiftUI

/// Profile tab: signed-out shows a sign-in call to action; signed-in shows the
/// account and a sign-out button.
struct ProfileView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var theme = AppTheme.shared
    @ObservedObject var player: Player
    @ObservedObject private var auth = Auth.shared
    @ObservedObject private var downloads = Downloads.shared
    @State private var showLogin = false
    @State private var showDownloads = false

    var body: some View {
        VStack(spacing: 20) {
            Circle()
                .fill(palette.heroGradient)
                .frame(width: 96, height: 96)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(palette.onSurface),
                )

            if auth.isLoggedIn {
                VStack(spacing: 4) {
                    Text(auth.accountName ?? "Signed in")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                    if let email = auth.accountEmail {
                        Text(email)
                            .font(.system(size: 14))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                }
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    Text("Sign out")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.onSurface)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(palette.onSurface.opacity(0.10))
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            } else {
                Text("Sign in to Blazify")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                Text("Sync your playlists, likes, and personalized home.")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button { showLogin = true } label: {
                    Text("Sign in with Google")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(palette.heroGradient)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }

            Button { showDownloads = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Downloads")
                    Spacer()
                    Text("\(downloads.tracks.count)").foregroundStyle(palette.onSurfaceVariant)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(palette.onSurface.opacity(0.35))
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(palette.onSurface.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.scaffold.ignoresSafeArea())
        .sheet(isPresented: $showLogin) { LoginView() }
        .sheet(isPresented: $showDownloads) { DownloadsView(player: player) }
    }
}
