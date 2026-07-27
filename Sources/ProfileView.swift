import SwiftUI

/// Profile tab: signed-out shows a sign-in call to action; signed-in shows the
/// account and a sign-out button.
struct ProfileView: View {
    @ObservedObject private var auth = Auth.shared
    @State private var showLogin = false

    var body: some View {
        VStack(spacing: 20) {
            Circle()
                .fill(Blaze.cardGradient)
                .frame(width: 96, height: 96)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white),
                )

            if auth.isLoggedIn {
                VStack(spacing: 4) {
                    Text(auth.accountName ?? "Signed in")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    if let email = auth.accountEmail {
                        Text(email)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    Text("Sign out")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            } else {
                Text("Sign in to Blazify")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Sync your playlists, likes, and personalized home.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button { showLogin = true } label: {
                    Text("Sign in with Google")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Blaze.gradient)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Blaze.scaffold.ignoresSafeArea())
        .sheet(isPresented: $showLogin) { LoginView() }
    }
}
