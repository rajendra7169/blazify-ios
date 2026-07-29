import SwiftUI

/// Settings → Backup and restore.
struct BackupRestoreView: View {
    @Environment(\.palette) private var palette
    @State private var exporting = false
    @State private var importing = false
    @State private var document = BackupDocument(data: Data())
    @State private var message: String?
    @State private var showRestoreConfirm = false
    @State private var pending: Data?

    var body: some View {
        SettingsPage(title: "Backup and restore") {
            SettingsGroup(title: "Backup") {
                SettingsLink(symbol: "square.and.arrow.up", title: "Save a backup",
                             subtitle: "Favourites, history and every setting, as one file") {
                    if let data = BlazifyBackup.make() {
                        document = BackupDocument(data: data)
                        exporting = true
                    }
                }
            }

            SettingsGroup(title: "Restore") {
                SettingsLink(symbol: "square.and.arrow.down", title: "Restore from a backup",
                             subtitle: "Replaces what's on this device") { importing = true }
            }

            Text("Playlists and subscriptions live on your YouTube account and "
                 + "come back when you sign in, so they aren't in the file. What's "
                 + "here is what only exists on this phone. Downloaded audio isn't "
                 + "included either — it would make the file enormous, and the songs "
                 + "re-download.")
                .font(.system(size: 12))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, 6)

            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 6)
            }
        }
        .fileExporter(isPresented: $exporting, document: document,
                      contentType: .json, defaultFilename: "Blazify-backup") { result in
            switch result {
            case .success: message = "Backup saved."
            case .failure(let error): message = "Couldn't save: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                // Files hands back a security-scoped URL; without this the read
                // fails with a permission error.
                let opened = url.startAccessingSecurityScopedResource()
                defer { if opened { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    message = "Couldn't read that file."
                    return
                }
                pending = data
                showRestoreConfirm = true
            case .failure(let error):
                message = "Couldn't open: \(error.localizedDescription)"
            }
        }
        .alert("Restore this backup?", isPresented: $showRestoreConfirm) {
            Button("Cancel", role: .cancel) { pending = nil }
            Button("Restore", role: .destructive) {
                guard let data = pending else { return }
                pending = nil
                if let count = BlazifyBackup.restore(from: data) {
                    message = "Restored \(count) items. Reopen Blazify to see everything applied."
                } else {
                    message = "That doesn't look like a Blazify backup."
                }
            }
        } message: {
            Text("Your current favourites, history and settings will be replaced.")
        }
    }
}
