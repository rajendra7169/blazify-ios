import SwiftUI
import UniformTypeIdentifiers

/// "On this phone" — the songs you brought in from Files, in the same list
/// design as everything else, with an import button in the toolbar.
struct LocalMusicView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var local = LocalMusic.shared

    @State private var picking = false
    @State private var notice: String?

    var body: some View {
        SongListScreen(
            title: "On this phone", tracks: local.tracks, player: player,
            emptyMessage: String(localized: "Bring in music from Files, iCloud Drive or anywhere else on your phone. It plays with no signal and never touches the network."),
            emptyActionTitle: String(localized: "Choose files"),
            emptyAction: { picking = true },
        )
        .overlay(alignment: .bottom) {
            if let notice { toast(notice) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { picking = true } label: {
                    if local.importing {
                        ProgressView().tint(palette.accent)
                    } else {
                        Image(systemName: "plus")
                    }
                }
                .tint(palette.accent)
                .disabled(local.importing)
                .accessibilityLabel("Add music from Files")
            }
        }
        // `.audio` is the supertype every audio format conforms to, so this one
        // entry covers mp3, m4a, wav, aiff and flac without listing them.
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            Task {
                let added = await local.importFiles(urls)
                show(message(added: added, of: urls.count))
            }
        }
    }

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.blaze(13, .semibold))
            .foregroundStyle(palette.onSurface)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(palette.surfaceHigh)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .padding(.bottom, 90)
            .transition(.opacity)
    }

    /// Say what actually happened — a file the decoder can't read is silently
    /// skipped otherwise, and the list just looks short.
    private func message(added: Int, of total: Int) -> String {
        if added == 0 { return String(localized: "Nothing could be added") }
        if added == total {
            return added == 1 ? String(localized: "Added 1 song")
                              : String(localized: "Added \(added) songs")
        }
        return String(localized: "Added \(added) of \(total) — the rest couldn't be read")
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation { notice = nil }
        }
    }
}
