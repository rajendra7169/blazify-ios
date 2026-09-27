import SwiftUI

/// Everyone you have turned away, and the way back in.
///
/// Without this, blocking is a one-way door: the menu that blocks an artist only
/// appears on their songs, and their songs are exactly what blocking hides.
struct BlockedArtistsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var blocked = BlockedArtists.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if blocked.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "nosign")
                            .font(.system(size: 34))
                            .foregroundStyle(palette.onSurfaceVariant)
                        Text("No one is blocked")
                            .font(.blaze(15, .semibold))
                            .foregroundStyle(palette.onSurface)
                        Text("Block an artist from any song's menu and they stay out of Home, search and radio.")
                            .font(.blaze(13))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    ForEach(blocked.entries, id: \.self) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.system(size: 20))
                                .foregroundStyle(palette.onSurfaceVariant)
                            Text(BlockedArtists.name(of: entry))
                                .font(.blaze(15))
                                .foregroundStyle(palette.onSurface)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button("Unblock") { blocked.remove(entry) }
                                .font(.blaze(13, .semibold))
                                .foregroundStyle(palette.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle("Blocked artists")
        .navigationBarTitleDisplayMode(.inline)
    }
}
