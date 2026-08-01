import SwiftUI

/// Privacy: pause/clear listen history and
/// pause/clear search history, each clear behind a confirmation. (the
/// third group is "Disable screenshot", which iOS doesn't allow apps to do.)
struct PrivacyView: View {
    @Environment(\.palette) private var palette

    @AppStorage("pauseListenHistory") private var pauseListenHistory = false
    @AppStorage("pauseSearchHistory") private var pauseSearchHistory = false

    @State private var confirmClearListen = false
    @State private var confirmClearSearch = false
    @ObservedObject private var searchHistory = SearchHistory.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                groupTitle("Listen history")
                group {
                    toggleRow(icon: "pause.circle", title: "Pause listen history",
                              subtitle: "New plays stop being recorded",
                              isOn: $pauseListenHistory)
                    divider
                    buttonRow(icon: "trash", title: "Clear listen history",
                              subtitle: "Removes what powers History, Stats and the home rails") {
                        confirmClearListen = true
                    }
                }

                groupTitle("Search history")
                group {
                    toggleRow(icon: "pause.circle", title: "Pause search history",
                              subtitle: "Searches stop being remembered",
                              isOn: $pauseSearchHistory)
                    divider
                    buttonRow(icon: "trash", title: "Clear search history",
                              subtitle: searchHistory.queries.isEmpty
                                ? "Nothing saved"
                                : "\(searchHistory.queries.count) recent searches") {
                        confirmClearSearch = true
                    }
                }
            }
            .padding(16)
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear your listen history?",
                            isPresented: $confirmClearListen, titleVisibility: .visible) {
            Button("Clear listen history", role: .destructive) { PlayHistory.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("History, Stats and the personalised home rails start over.")
        }
        .confirmationDialog("Clear your search history?",
                            isPresented: $confirmClearSearch, titleVisibility: .visible) {
            Button("Clear search history", role: .destructive) { SearchHistory.shared.clear() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Pieces

    private func groupTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.blaze(12, .bold))
            .tracking(1.2)
            .foregroundStyle(palette.onSurfaceVariant)
            .padding(.leading, 6)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var divider: some View {
        Divider().overlay(palette.separator).padding(.leading, 66)
    }

    private func toggleRow(icon: String, title: String, subtitle: String,
                           isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            iconChip(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.blaze(15, .semibold))
                    .foregroundStyle(palette.onSurface)
                Text(subtitle)
                    .font(.blaze(12.5))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).labelsHidden().tint(palette.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func buttonRow(icon: String, title: String, subtitle: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                iconChip(icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.blaze(15, .semibold))
                        .foregroundStyle(palette.onSurface)
                    Text(subtitle)
                        .font(.blaze(12.5))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.blaze(13))
                    .foregroundStyle(palette.onSurface.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconChip(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.blaze(18))
            .foregroundStyle(palette.accent)
            .frame(width: 38, height: 38)
            .background(palette.accent.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
