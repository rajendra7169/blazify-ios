import SwiftUI
import UIKit

/// One GitHub release, as the changelog shows it.
struct ReleaseInfo: Identifiable {
    var id: String { tag }
    let tag: String
    let date: String     // yyyy-MM-dd
    let body: String     // markdown
}

/// Fetches release notes from GitHub.
enum Changelog {
    /// The repo is private today, so this returns nothing yet; the page shows
    /// its empty state. Flip the repo public and the notes appear — no code
    /// change needed.
    static let repo = "rajendra7169/blazify-ios"
    static var releasesURL: URL { URL(string: "https://github.com/\(repo)/releases")! }

    static func releases() async -> [ReleaseInfo] {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return arr.compactMap { item in
            guard let tag = item["tag_name"] as? String else { return nil }
            let published = (item["published_at"] as? String) ?? ""
            return ReleaseInfo(tag: tag,
                               date: published.components(separatedBy: "T").first ?? "",
                               body: (item["body"] as? String) ?? "")
        }
    }
}

/// Changelog: a sheet with the big centred
/// title, a wavy accent divider, one card per release (version chip · date ·
/// markdown notes) and the "View on GitHub" floating button.
struct ChangelogView: View {
    @Environment(\.palette) private var palette

    @State private var releases: [ReleaseInfo] = []
    @State private var loading = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Changelog")
                        .font(.blaze(32, .bold))
                        .foregroundStyle(palette.onSurface)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)

                    // The full-width wavy accent rule under the title.
                    WavePath(amplitude: 3, wavelength: 24, phase: 0)
                        .stroke(palette.accent,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(height: 12)
                        .padding(.horizontal, 32)

                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                    } else if releases.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "shippingbox")
                                .font(.blaze(40))
                                .foregroundStyle(palette.onSurfaceVariant.opacity(0.6))
                            Text("No release notes yet")
                                .font(.blaze(16, .semibold))
                                .foregroundStyle(palette.onSurface)
                            Text("Release notes will show up here once Blazify's releases are published.")
                                .font(.blaze(13))
                                .foregroundStyle(palette.onSurfaceVariant)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        ForEach(releases) { release in
                            releaseItem(release)
                        }
                    }

                    Spacer().frame(height: 80)   // room above the FAB
                }
                .padding(.horizontal, 16)
            }

            // "View on GitHub" — the sheet's floating action.
            Link(destination: Changelog.releasesURL) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.blaze(15, .semibold))
                    Text("View on GitHub")
                        .font(.blaze(15, .semibold))
                }
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(palette.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            }
            .padding(16)
        }
        .background(palette.surface)
        .presentationBackground(palette.surface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            releases = await Changelog.releases()
            loading = false
        }
    }

    // MARK: One release

    private func releaseItem(_ release: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(release.tag)
                    .font(.blaze(13, .semibold))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(palette.accent)
                    .clipShape(Capsule())
                Spacer()
                Text(release.date)
                    .font(.blaze(13))
                    .foregroundStyle(palette.onSurfaceVariant)
            }

            MarkdownBody(text: release.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(palette.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// The changelog's small markdown renderer, ported from MarkdownText: `#`
/// headers centred by level, `-`/`*` bullets, and `@user` / URLs as links.
struct MarkdownBody: View {
    @Environment(\.palette) private var palette
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                render(line)
            }
        }
    }

    private var lines: [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder private func render(_ line: String) -> some View {
        if line.hasPrefix("#") {
            let level = line.prefix(while: { $0 == "#" }).count
            let title = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
            Text(title)
                .font(.system(size: level == 1 ? 22 : (level == 2 ? 18 : 15), weight: .bold))
                .foregroundStyle(palette.onSurface)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 8) {
                Text("•").foregroundStyle(palette.accent)
                linked(String(line.dropFirst(2)))
            }
        } else {
            linked(line)
        }
    }

    /// `@user` and bare URLs become tappable, everything else plain text.
    private func linked(_ raw: String) -> some View {
        var attributed = AttributedString(raw)
        let ns = raw as NSString
        let pattern = #"(@[A-Za-z0-9_-]+)|(https?://[^\s]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
                let token = ns.substring(with: match.range)
                let target = token.hasPrefix("@")
                    ? "https://github.com/\(token.dropFirst())" : token
                if let range = attributed.range(of: token), let url = URL(string: target) {
                    attributed[range].link = url
                    attributed[range].foregroundColor = palette.accent
                }
            }
        }
        return Text(attributed)
            .font(.blaze(14))
            .foregroundStyle(palette.onSurface)
            .tint(palette.accent)
    }
}
