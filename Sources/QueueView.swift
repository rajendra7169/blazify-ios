import SwiftUI

/// The play queue: every track with the now-playing row highlighted; tap to jump.
struct QueueView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { pair in
                    let active = pair.offset == player.index
                    Button {
                        player.jump(to: pair.offset)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: pair.element.thumbnailURL) {
                                palette.onSurface.opacity(0.10)
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.element.title)
                                    .font(.subheadline)
                                    .foregroundStyle(active ? palette.accent : palette.onSurface)
                                    .lineLimit(1)
                                Text(pair.element.artist)
                                    .font(.caption)
                                    .foregroundStyle(palette.onSurfaceVariant)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if active {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption)
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(active ? palette.onSurface.opacity(0.08) : Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(palette.accent)
                }
            }
        }
    }
}
