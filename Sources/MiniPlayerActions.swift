import SwiftUI

/// The buttons a person can put on the mini-player, and which three each design shows until they
/// choose, as on Android. Chosen per design, so changing design never loses a choice.
enum MiniPlayerAction: String, CaseIterable, Identifiable {
    // Stable, stored: never rename.
    case playPause = "play_pause"
    case previous
    case next
    case like
    case addToPlaylist = "add_to_playlist"
    case viewArtist = "view_artist"
    case startRadio = "start_radio"
    case download
    case sleepTimer = "sleep_timer"
    case shuffle
    case `repeat`

    var id: String { rawValue }

    /// Always this many: fewer leaves the bar looking empty, more leaves the title no room.
    static let count = 3

    var title: String {
        switch self {
        case .playPause: String(localized: "Play / pause")
        case .previous: String(localized: "Previous")
        case .next: String(localized: "Next")
        case .like: String(localized: "Like")
        case .addToPlaylist: String(localized: "Add to playlist")
        case .viewArtist: String(localized: "View artist")
        case .startRadio: String(localized: "Start radio")
        case .download: String(localized: "Download")
        case .sleepTimer: String(localized: "Sleep timer")
        case .shuffle: String(localized: "Shuffle")
        case .repeat: String(localized: "Repeat")
        }
    }

    /// Its symbol at rest, for the chooser.
    var icon: String {
        switch self {
        case .playPause: "play.fill"
        case .previous: "backward.end.fill"
        case .next: "forward.end.fill"
        case .like: "heart"
        case .addToPlaylist: "plus"
        case .viewArtist: "person"
        case .startRadio: "dot.radiowaves.left.and.right"
        case .download: "arrow.down.circle"
        case .sleepTimer: "moon.zzz"
        case .shuffle: "shuffle"
        case .repeat: "repeat"
        }
    }

    /// What each design showed before there was a choice, so nobody's mini-player changes by itself.
    static func defaults(for design: MiniPlayerDesign) -> [MiniPlayerAction] {
        switch design {
        case .flat: [.playPause, .next, .like]
        case .rounded: [.previous, .playPause, .next]
        case .modern, .floating: [.viewArtist, .addToPlaylist, .like]
        }
    }

    static func key(for design: MiniPlayerDesign) -> String { "miniPlayerButtons_\(design.rawValue)" }

    /// Always `count` buttons: blank means the design's own; an id from a later version is
    /// skipped, and any gap is filled from the design's own, so the bar is never short.
    static func decode(_ text: String, for design: MiniPlayerDesign) -> [MiniPlayerAction] {
        var chosen: [MiniPlayerAction] = []
        for id in text.split(separator: ",") {
            if let action = MiniPlayerAction(rawValue: id.trimmingCharacters(in: .whitespaces)),
               !chosen.contains(action), chosen.count < count {
                chosen.append(action)
            }
        }
        for action in defaults(for: design) + allCases where chosen.count < count && !chosen.contains(action) {
            chosen.append(action)
        }
        return chosen
    }
}

extension LookFeel {
    /// The three buttons shown on the mini-player in [design].
    func miniPlayerButtons(for design: MiniPlayerDesign) -> [MiniPlayerAction] {
        MiniPlayerAction.decode(UserDefaults.standard.string(forKey: MiniPlayerAction.key(for: design)) ?? "", for: design)
    }

    func setMiniPlayerButtons(_ actions: [MiniPlayerAction], for design: MiniPlayerDesign) {
        objectWillChange.send()
        UserDefaults.standard.set(actions.map(\.rawValue).joined(separator: ","), forKey: MiniPlayerAction.key(for: design))
    }

    /// Back to the design's own buttons.
    func resetMiniPlayerButtons(for design: MiniPlayerDesign) {
        objectWillChange.send()
        UserDefaults.standard.removeObject(forKey: MiniPlayerAction.key(for: design))
    }
}

/// Look & Feel › Mini-player › Buttons: three places in a row; tap a place, then a button to put
/// there. A button already on the bar swaps with it.
struct MiniPlayerButtonsChooser: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var look = LookFeel.shared
    @State private var slot = 0

    var body: some View {
        let design = look.miniPlayerDesign
        let chosen = look.miniPlayerButtons(for: design)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Buttons")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                Button("Reset") { look.resetMiniPlayerButtons(for: design) }
                    .font(.system(size: 13, weight: .semibold))
                    .tint(palette.accent)
            }
            Text("Tap a place, then the button to put there.")
                .font(.system(size: 12))
                .foregroundStyle(palette.onSurfaceVariant)
            HStack(spacing: 10) {
                ForEach(0 ..< MiniPlayerAction.count, id: \.self) { i in
                    Button { slot = i } label: {
                        VStack(spacing: 4) {
                            Image(systemName: chosen[i].icon).font(.system(size: 18))
                            Text(chosen[i].title).font(.system(size: 10)).lineLimit(1)
                        }
                        .foregroundStyle(slot == i ? palette.accent : palette.onSurface)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(slot == i ? palette.accent.opacity(0.14) : palette.onSurface.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(slot == i ? palette.accent : .clear, lineWidth: 1.5),
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Place \(i + 1): \(chosen[i].title)")
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                ForEach(MiniPlayerAction.allCases) { action in
                    let used = chosen.contains(action)
                    Button { put(action, design: design, chosen: chosen) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: action.icon).font(.system(size: 16))
                            Text(action.title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(used ? palette.accent : palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.onSurface.opacity(used ? 0.10 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func put(_ action: MiniPlayerAction, design: MiniPlayerDesign, chosen: [MiniPlayerAction]) {
        var next = chosen
        if let from = next.firstIndex(of: action) {
            next.swapAt(from, slot)
        } else {
            next[slot] = action
        }
        look.setMiniPlayerButtons(next, for: design)
        slot = (slot + 1) % MiniPlayerAction.count
    }
}
