import SwiftUI

/// Listening history, ported from HistoryScreen.kt: a Local/Remote switch, with
/// plays grouped by date. Local buckets come from our own event log; remote ones
/// are whatever YouTube Music itself has recorded for the account.
struct HistoryView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var auth = Auth.shared

    @State private var source: Source = .local
    @State private var remote: [YouTube.HistorySection] = []
    @State private var loading = false
    @State private var query = ""
    @State private var searching = false

    enum Source: String, CaseIterable, Identifiable {
        case local, remote
        var id: String { rawValue }
        var title: String { self == .local ? "On this device" : "YouTube Music" }
    }

    /// Whatever the current source says, as (heading, songs) pairs.
    private var sections: [(title: String, tracks: [Track])] {
        let raw: [(String, [Track])] = source == .local
            ? PlayHistory.grouped.map { ($0.bucket.title, $0.tracks) }
            : remote.map { ($0.title, $0.tracks) }

        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return raw.map { (title: $0.0, tracks: $0.1) } }
        return raw.compactMap { title, tracks in
            let hits = tracks.filter {
                $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
            }
            return hits.isEmpty ? nil : (title: title, tracks: hits)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if auth.isLoggedIn { sourcePicker }

                if loading && source == .remote {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonBox(height: 56, corner: 10)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                } else if sections.isEmpty {
                    Text(source == .local
                         ? "Nothing played yet — your history will appear here."
                         : "No history on your YouTube Music account.")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 32)
                        .padding(.top, 60)
                }

                ForEach(sections, id: \.title) { section in
                    Text(section.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    ForEach(Array(section.tracks.enumerated()), id: \.element.id) { index, track in
                        Button {
                            player.play(section.tracks, startAt: index)
                            player.showFullPlayer = true
                        } label: {
                            TrackRow(track: track)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { searching.toggle() }
                    if !searching { query = "" }
                } label: {
                    Image(systemName: searching ? "xmark" : "magnifyingglass")
                        .foregroundStyle(palette.onSurface)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if searching {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(palette.onSurfaceVariant)
                    TextField("Search history", text: $query)
                        .foregroundStyle(palette.onSurface)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(palette.surfaceHigh)
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(palette.scaffold)
            }
        }
        .task(id: source) {
            guard source == .remote, remote.isEmpty else { return }
            loading = true
            let sections = await YouTube.musicHistory()
            await MainActor.run {
                remote = sections
                loading = false
            }
        }
    }

    private var sourcePicker: some View {
        HStack(spacing: 8) {
            ForEach(Source.allCases) { option in
                let active = option == source
                Text(option.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? palette.onAccent : palette.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(active ? AnyShapeStyle(palette.accent)
                                       : AnyShapeStyle(palette.onSurface.opacity(0.06)))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .onTapGesture { source = option }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
