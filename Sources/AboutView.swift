import SwiftUI

/// About, ported from AboutScreen.kt: the themed brand hero, the developer card
/// with avatar and socials, and the Buy-me-a-coffee QR — same person, same
/// links, same QR as the Android app.
struct AboutView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var showCoffee = false

    private let website = URL(string: "https://www.rajendrapandey.info.np/")!
    private let github = URL(string: "https://github.com/rajendra7169")!
    private let instagram = URL(string: "https://www.instagram.com/raja.indra7169")!
    private let avatar = URL(string: "https://github.com/rajendra7169.png")!

    private let aboutMe = """
        I'm Rajendra Pandey, an independent app developer from Nepal who loves \
        turning ideas into polished, everyday experiences. Blazify is my take on \
        music streaming — fast, beautiful and personal — crafted from the ground \
        up. I care about the little details that make an app feel effortless, and \
        I'm always tinkering to make it better. Thanks for being here and letting \
        my work be part of your day.
        """

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                Spacer().frame(height: 20)
                developerCard
                Spacer().frame(height: 40)

                Text("Made with ❤️ by Rajendra Pandey")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 16)
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCoffee) {
            coffeeSheet
                .presentationDetents([.medium, .large])
                .environment(\.palette, palette)
        }
    }

    // MARK: Hero

    private var hero: some View {
        // The gradient follows the theme accent, as Android's does.
        let start = palette.accent
        let end = start.mixed(with: .black, 0.24)
        let ink: Color = start.isLight ? .black : .white

        return VStack(spacing: 12) {
            Image(bundleImage: "blaze_logo_white")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 88, height: 88)
                .foregroundStyle(ink)

            Text("Blazify")
                .font(.system(size: 34, weight: .black))
                .tracking(-0.5)
                .foregroundStyle(ink)

            HStack(spacing: 8) {
                heroChip(appVersion, ink: ink)
                heroChip("STABLE", ink: ink)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(LinearGradient(colors: [start, end],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.top, 16)
    }

    private func heroChip(_ text: String, ink: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(ink.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(v ?? "0.1")"
    }

    // MARK: Developer

    private var developerCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                RemoteImage(url: avatar, size: 96) {
                    Circle().fill(palette.surfaceHigh)
                        .overlay(Image(systemName: "person.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(palette.onSurfaceVariant))
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rajendra Pandey")
                        .font(.system(size: 22, weight: .black))
                        .tracking(-0.5)
                        .foregroundStyle(palette.onSurface)
                    Text("Developer")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                socialButton("globe", url: website)
                socialButton("chevron.left.forwardslash.chevron.right", url: github)
                socialButton("camera", url: instagram)
            }

            Text(aboutMe)
                .font(.system(size: 14))
                .lineSpacing(5)
                .foregroundStyle(palette.onSurfaceVariant)

            Button { showCoffee = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 18))
                    Text("Buy me a coffee")
                        .font(.system(size: 16, weight: .heavy))
                }
                .foregroundStyle(palette.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(palette.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func socialButton(_ icon: String, url: URL) -> some View {
        Link(destination: url) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(palette.onSurface)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(palette.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: Coffee QR

    private var coffeeSheet: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 24)
            Text("Buy me a coffee")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(palette.onSurface)
            Text("Scan the code to support Blazify")
                .font(.system(size: 14))
                .foregroundStyle(palette.onSurfaceVariant)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 20)

            // The QR sits on white whatever the theme, or it won't scan.
            Image(bundleImage: "coffee_qr")
                .resizable()
                .scaledToFit()
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 32)

            Spacer(minLength: 12)
            Button("Dismiss") { showCoffee = false }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.accent)
            Spacer().frame(height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.surface)
        .presentationBackground(palette.surface)
    }
}
