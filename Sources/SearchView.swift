import SwiftUI

/// Explore — the search experience, ported from OnlineSearchScreen.kt.
///
/// Idle it shows recent-search chips over browse tiles; typing brings live
/// suggestions (playable songs first, then completed queries, with matching
/// history above both); submitting runs the full song search.
struct SearchView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    /// True when pushed from Home's search pill rather than shown as the tab —
    /// the nav bar is hidden either way, so we need our own way back.
    var pushed = false
    @ObservedObject private var history = SearchHistory.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Track] = []
    @State private var suggestions: [String] = []
    @State private var suggestedSongs: [Track] = []
    @State private var moods: [MoodItem] = []
    @State private var searching = false
    @State private var didSearch = false
    @State private var moodRoute: MoodItem?
    /// Cancels an in-flight suggestion fetch when another keystroke lands.
    @State private var suggestTask: Task<Void, Never>?
    /// Set while `run` rewrites the field, so its own edit isn't treated as typing.
    @State private var suppressSuggest = false

    @FocusState private var fieldFocused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if searching {
                        SkeletonTrackList(rows: 8).padding(.top, 8)
                    } else if !results.isEmpty {
                        resultRows
                    } else if !trimmed.isEmpty {
                        suggestionList
                    } else {
                        idleContent
                    }
                }
                .playerBottomPadding()
            }
            // Swipe the results to put the keyboard away.
            .scrollDismissesKeyboard(.immediately)
        }
        .background(palette.scaffold.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $moodRoute) { MoodDetailView(mood: $0, player: player) }
        .task { if moods.isEmpty { moods = await YouTube.moods() } }
    }

    // MARK: Field

    private var searchField: some View {
        HStack(spacing: 12) {
            if pushed {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.onSurface)
                }
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.onSurfaceVariant)
            }

            TextField("Songs, artists, albums…", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(palette.onSurface)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($fieldFocused)
                .onSubmit { run(trimmed) }
                .onChange(of: query) {
                    if suppressSuggest { suppressSuggest = false } else { suggest() }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    suggestions = []
                    suggestedSongs = []
                    didSearch = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(palette.onSurface.opacity(0.08))
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: Idle — recent searches, then somewhere to go

    @ViewBuilder private var idleContent: some View {
        if !history.queries.isEmpty {
            HStack {
                Text("Recent searches")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                Button("Clear") { history.clear() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            // Chips, as Android's recent-search row does — ✕ removes one.
            FlowChips(items: Array(history.queries.prefix(12))) { entry in
                run(entry)
            } onDelete: { entry in
                history.remove(entry)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }

        if !moods.isEmpty {
            Text("Browse")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(moods.prefix(12)) { mood in
                    browseTile(mood)
                }
            }
            .padding(.horizontal, 16)
        } else if history.queries.isEmpty {
            Text("Search for a song, artist or album")
                .font(.system(size: 14))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        }
    }

    /// A browse tile sized by the grid, so it can't use the fixed-width card.
    private func browseTile(_ mood: MoodItem) -> some View {
        let seed = Color(hex: mood.colorARGB & 0xFFFFFF)
        return Button { moodRoute = mood } label: {
            Text(mood.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(seed.isLight ? .black : .white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .bottomLeading)
                .padding(14)
                .background(
                    LinearGradient(colors: [seed.mixed(with: .white, 0.24), seed],
                                   startPoint: .top, endPoint: .bottom),
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Typing — songs first, then queries

    @ViewBuilder private var suggestionList: some View {
        let matches = history.matching(trimmed)

        ForEach(matches, id: \.self) { entry in
            suggestionRow(entry, icon: "clock.arrow.circlepath") { run(entry) }
        }

        // Playable results lead: tapping one starts music instead of another search.
        ForEach(suggestedSongs.prefix(6)) { song in
            Button {
                history.add(trimmed)
                player.play([song], startAt: 0)
                player.showFullPlayer = true
            } label: {
                TrackRow(track: song)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }

        if !suggestedSongs.isEmpty, !suggestions.isEmpty {
            Divider().overlay(palette.separator)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }

        ForEach(suggestions.filter { s in !matches.contains(s) }, id: \.self) { suggestion in
            suggestionRow(suggestion, icon: "magnifyingglass") { run(suggestion) }
        }

        if suggestedSongs.isEmpty, suggestions.isEmpty, didSearch {
            Text("No results")
                .font(.system(size: 14))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        }
    }

    private func suggestionRow(_ text: String, icon: String,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(palette.onSurfaceVariant)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
            Spacer(minLength: 0)
            // Lets you refine a suggestion instead of running it as-is.
            Button {
                query = text
                suggest()
            } label: {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private var resultRows: some View {
        ForEach(Array(results.enumerated()), id: \.element.id) { index, track in
            Button {
                player.play(results, startAt: index)
                player.showFullPlayer = true
            } label: {
                TrackRow(track: track)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    /// Debounced so a fast typist fires one request, not one per keystroke.
    private func suggest() {
        suggestTask?.cancel()
        results = []
        let q = trimmed
        guard !q.isEmpty else {
            suggestions = []
            suggestedSongs = []
            didSearch = false
            return
        }
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            let found = await YouTube.searchSuggestions(q)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                suggestions = found.queries
                suggestedSongs = found.songs
                didSearch = true
            }
        }
    }

    private func run(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        suggestTask?.cancel()
        suppressSuggest = true
        query = q
        history.add(q)
        fieldFocused = false
        searching = true
        didSearch = true
        Task {
            let found = await YouTube.search(q)
            await MainActor.run {
                results = found
                searching = false
            }
        }
    }
}

/// A wrapping row of removable chips — the recent-search row from Android.
struct FlowChips: View {
    @Environment(\.palette) private var palette
    let items: [String]
    let onTap: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        // Simple greedy wrap: SwiftUI has no flow layout before iOS 16's Layout
        // protocol, and rows of short chips lay out fine measured by character
        // count against the available width.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows().enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { chip(for: $0) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chip(for entry: String) -> some View {
        HStack(spacing: 6) {
            Text(entry)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.onSurface)
                .lineLimit(1)
            Button { onDelete(entry) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(palette.onSurface.opacity(0.06))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture { onTap(entry) }
    }

    /// Pack chips into rows of roughly a screen's width.
    private func rows() -> [[String]] {
        var out: [[String]] = []
        var current: [String] = []
        var width = 0
        for entry in items {
            let cost = entry.count + 5
            if width + cost > 38, !current.isEmpty {
                out.append(current)
                current = []
                width = 0
            }
            current.append(entry)
            width += cost
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

/// One search-result row: art, title, artist.
struct TrackRow: View {
    @Environment(\.palette) private var palette
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: track.thumbnailURL, size: 52) {
                palette.onSurface.opacity(0.10)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.subheadline).foregroundStyle(palette.onSurface)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption).foregroundStyle(palette.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            DownloadRing(videoId: track.videoId)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// The ring on a row that's downloading. It observes Downloads on its own so a
/// progress tick invalidates this 18pt view and not the whole list row.
struct DownloadRing: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var downloads = Downloads.shared
    let videoId: String

    var body: some View {
        if downloads.state(videoId) == .downloading {
            let value = downloads.progress[videoId] ?? 0
            ZStack {
                Circle()
                    .stroke(palette.onSurfaceVariant.opacity(0.25), lineWidth: 2.5)
                Circle()
                    // A sliver always shows, so the ring reads as "started"
                    // rather than empty while the first range is in flight.
                    .trim(from: 0, to: max(value, 0.03))
                    .stroke(palette.accent,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.25), value: value)
            }
            .frame(width: 18, height: 18)
            .padding(.leading, 6)
            .transition(.opacity)
        }
    }
}
