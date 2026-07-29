import SwiftUI

/// Settings → Stream sources, ported from `StreamSourcesSettings.kt`: the order
/// InnerTube clients are tried when resolving a song's audio. Android lists
/// seven; only three answer for music with a direct URL, so only those are here
/// — the rest error, come back unplayable, or demand a login.
struct StreamSourcesView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var prefs = StreamPrefs.shared

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(prefs.order) { client in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(client.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(palette.onSurface)
                                Text(client.blurb)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                            Spacer(minLength: 8)
                            if client == prefs.order.first {
                                Text("FIRST")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(palette.onAccent)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(palette.accent)
                                    .clipShape(Capsule())
                            }
                        }
                        .listRowBackground(palette.surface)
                    }
                    .onMove { from, to in prefs.order.move(fromOffsets: from, toOffset: to) }
                } header: {
                    Text("Tried in this order")
                        .foregroundStyle(palette.onSurfaceVariant)
                } footer: {
                    Text("If the first source is refused, the next one is tried, so "
                         + "playback keeps working when YouTube changes something. "
                         + "Android VR is the only source that reports track loudness, "
                         + "which volume normalisation needs.")
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle("Stream sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
