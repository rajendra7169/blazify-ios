import SwiftUI

/// Whoever is signed in, shown as themselves.
///
/// The Android screens put the account's own photo in the top-right corner of
/// Home, Yours and Library rather than a person glyph, because a photo says at a
/// glance which account the app is on.
struct AccountAvatar: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var auth = Auth.shared

    var size: CGFloat = 32

    var body: some View {
        if auth.isLoggedIn, let photo = auth.accountPhoto, let url = URL(string: photo) {
            RemoteImage(url: url, size: size) { Circle().fill(palette.heroGradient) }
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: auth.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.system(size: size * 0.82))
                .foregroundStyle(auth.isLoggedIn ? palette.accent : palette.onSurface)
                .frame(width: size, height: size)
        }
    }
}
