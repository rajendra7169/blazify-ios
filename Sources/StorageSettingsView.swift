import SwiftUI

/// Storage, ported from StorageSettings.kt: downloads, the song cache with its
/// on/off switch and cap, and the image cache with its own cap — each showing
/// what it's using and offering a way to clear it.
struct StorageSettingsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var cache = AudioCache.shared

    @State private var songCacheOn = AudioCache.shared.isEnabled
    @State private var songLimitMB = AudioCache.shared.limitMB
    @State private var imageLimitMB = ImageCacheSettings.limitMB
    @State private var imageUsed: Int64 = 0

    @State private var confirmClearDownloads = false
    @State private var confirmClearCache = false
    @State private var confirmClearImages = false

    /// Android's exact ladder: 0 disables, -1 is unlimited.
    private let songValues = [0, 128, 256, 512, 1024, 2048, 4096, 8192, -1]
    private let imageValues = [0, 128, 256, 512, 1024, 2048, 4096, 8192]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                downloadsCard
                songCacheCard
                imageCacheCard
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
            imageUsed = ImageCacheSettings.used
        }
        .confirmationDialog("Delete every downloaded song?",
                            isPresented: $confirmClearDownloads, titleVisibility: .visible) {
            Button("Clear downloads", role: .destructive) { downloads.clearAll() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear the song cache?",
                            isPresented: $confirmClearCache, titleVisibility: .visible) {
            Button("Clear song cache", role: .destructive) { cache.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloaded songs are kept — only the automatic cache is emptied.")
        }
        .confirmationDialog("Clear cached artwork?",
                            isPresented: $confirmClearImages, titleVisibility: .visible) {
            Button("Clear image cache", role: .destructive) {
                ImageCacheSettings.clear()
                imageUsed = 0
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Cards

    private var downloadsCard: some View {
        card {
            header("Downloaded songs",
                   "\(downloads.tracks.count) song\(downloads.tracks.count == 1 ? "" : "s") · \(format(downloads.sizeBytes))")
            clearButton("Clear all downloads") { confirmClearDownloads = true }
        }
    }

    private var songCacheCard: some View {
        card {
            HStack {
                header("Song cache", "\(cache.tracks.count) song\(cache.tracks.count == 1 ? "" : "s") kept automatically")
                Spacer(minLength: 12)
                Toggle("", isOn: $songCacheOn)
                    .labelsHidden()
                    .tint(palette.accent)
                    .onChange(of: songCacheOn) {
                        UserDefaults.standard.set(songCacheOn, forKey: "enableSongCache")
                    }
            }

            if songCacheOn {
                usage(cache.sizeBytes, cap: cache.limitBytes)
                limitPicker(values: songValues, selected: songLimitMB) { mb in
                    songLimitMB = mb
                    UserDefaults.standard.set(mb, forKey: "songCacheLimitMB")
                    cache.refreshSize()
                }
                clearButton("Clear song cache") { confirmClearCache = true }
            } else {
                Text("Songs won't be kept on disk after playing.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
        }
    }

    private var imageCacheCard: some View {
        card {
            header("Image cache", "Album art kept on disk")
            usage(imageUsed, cap: ImageCacheSettings.limitBytes)
            limitPicker(values: imageValues, selected: imageLimitMB) { mb in
                imageLimitMB = mb
                ImageCacheSettings.setLimit(mb)
                imageUsed = ImageCacheSettings.used
            }
            clearButton("Clear image cache") { confirmClearImages = true }
        }
    }

    // MARK: Pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.onSurface)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(palette.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func usage(_ used: Int64, cap: Int64?) -> some View {
        if let cap, cap > 0 {
            ProgressView(value: min(Double(used) / Double(cap), 1))
                .tint(palette.accent)
            Text("\(format(used)) of \(format(cap))")
                .font(.system(size: 13))
                .foregroundStyle(palette.onSurfaceVariant)
        } else {
            Text("\(format(used)) used\(cap == nil ? " · unlimited" : "")")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.accent)
        }
    }

    private func limitPicker(values: [Int], selected: Int,
                             onPick: @escaping (Int) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { mb in
                    let active = selected == mb
                    Text(label(for: mb))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? palette.onAccent : palette.onSurface)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(active ? AnyShapeStyle(palette.accent)
                                           : AnyShapeStyle(palette.onSurface.opacity(0.06)))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { onPick(mb) }
                }
            }
        }
    }

    private func clearButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, role: .destructive, action: action)
            .font(.system(size: 14, weight: .semibold))
    }

    private func label(for mb: Int) -> String {
        switch mb {
        case 0: return "Off"
        case ..<0: return "Unlimited"
        default: return format(Int64(mb) * 1024 * 1024)
        }
    }

    private func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// The on-disk artwork cache — it's `URLCache`, so its size and limit live here
/// rather than on a type of our own.
enum ImageCacheSettings {
    static var limitMB: Int {
        guard UserDefaults.standard.object(forKey: "imageCacheLimitMB") != nil else { return 1024 }
        return UserDefaults.standard.integer(forKey: "imageCacheLimitMB")
    }

    static var limitBytes: Int64? { limitMB <= 0 ? nil : Int64(limitMB) * 1024 * 1024 }

    static var used: Int64 { Int64(URLCache.shared.currentDiskUsage) }

    static func setLimit(_ mb: Int) {
        UserDefaults.standard.set(mb, forKey: "imageCacheLimitMB")
        URLCache.shared.diskCapacity = mb <= 0 ? 0 : mb * 1024 * 1024
        if mb == 0 { clear() }
    }

    static func clear() {
        URLCache.shared.removeAllCachedResponses()
        ImageCache.store.removeAllObjects()
    }
}
