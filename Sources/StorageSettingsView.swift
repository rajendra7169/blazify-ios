import SwiftUI

/// Storage, ported from StorageSettings.kt: what downloads and the song cache
/// are using, a cap for the cache, and a way to clear each.
struct StorageSettingsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var cache = AudioCache.shared

    @State private var limitMB = UserDefaults.standard.integer(forKey: "songCacheLimitMB")
    @State private var confirmClearDownloads = false
    @State private var confirmClearCache = false

    /// The choices Android offers for the song-cache cap.
    private let options: [Int] = [128, 256, 512, 1024, 2048, 4096]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                section(
                    title: "Downloaded songs",
                    subtitle: "\(downloads.tracks.count) song\(downloads.tracks.count == 1 ? "" : "s")",
                    used: downloads.sizeBytes, limit: nil,
                    clearTitle: "Clear all downloads",
                ) { confirmClearDownloads = true }

                section(
                    title: "Song cache",
                    subtitle: "\(cache.tracks.count) song\(cache.tracks.count == 1 ? "" : "s") kept automatically",
                    used: cache.sizeBytes, limit: cache.limitBytes,
                    clearTitle: "Clear song cache",
                ) { confirmClearCache = true }

                cacheLimitPicker
            }
            .padding(16)
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            downloads.refreshSize()
            cache.refreshSize()
        }
        .confirmationDialog("Delete every downloaded song?",
                            isPresented: $confirmClearDownloads, titleVisibility: .visible) {
            Button("Clear downloads", role: .destructive) { downloads.clearAll() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear the song cache?",
                            isPresented: $confirmClearCache, titleVisibility: .visible) {
            Button("Clear cache", role: .destructive) { cache.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloaded songs are kept — only the automatic cache is emptied.")
        }
    }

    // MARK: Pieces

    private func section(title: String, subtitle: String, used: Int64, limit: Int64?,
                         clearTitle: String, clear: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.onSurface)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(palette.onSurfaceVariant)

            if let limit {
                // Usage against the cap, as Android's progress bar shows.
                ProgressView(value: min(Double(used) / Double(max(limit, 1)), 1))
                    .tint(palette.accent)
                Text("\(format(used)) of \(format(limit))")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.onSurfaceVariant)
            } else {
                Text(format(used))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.accent)
            }

            Button(clearTitle, role: .destructive, action: clear)
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cacheLimitPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Maximum cache size")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.onSurface)
            Text("Older songs are dropped once the cache passes this.")
                .font(.system(size: 13))
                .foregroundStyle(palette.onSurfaceVariant)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { mb in
                        let active = effectiveLimit == mb
                        Text(format(Int64(mb) * 1024 * 1024))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? palette.onAccent : palette.onSurface)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(active ? AnyShapeStyle(palette.accent)
                                               : AnyShapeStyle(palette.onSurface.opacity(0.06)))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                            .onTapGesture {
                                limitMB = mb
                                UserDefaults.standard.set(mb, forKey: "songCacheLimitMB")
                                cache.refreshSize()
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var effectiveLimit: Int { limitMB > 0 ? limitMB : 512 }

    private func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
