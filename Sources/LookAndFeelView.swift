import SwiftUI

/// Look & Feel, ported from LookAndFeelScreen.kt: one pinned phone-frame
/// preview whose interior follows the active tab, an amber pill tab strip, and
/// the controls for that tab underneath. Changing anything updates the preview
/// and the real app at once.
struct LookAndFeelView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var look = LookFeel.shared
    @ObservedObject private var theme = AppTheme.shared

    @State private var tab: LookFeelTab = .theme

    enum LookFeelTab: String, CaseIterable, Identifiable {
        case theme, player, mini, lyrics, home
        var id: String { rawValue }
        var title: String {
            switch self {
            case .theme: String(localized: "Theme")
            case .player: String(localized: "Player")
            case .mini: String(localized: "Mini player")
            case .lyrics: String(localized: "Lyrics")
            case .home: String(localized: "Home")
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            // Android sizes the frame at 48% of the screen, clamped 260–480.
            let frameHeight = min(max(geo.size.height * 0.48, 260), 480)

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 12)

                    LookFeelPhoneFrame {
                        preview
                    }
                    .frame(height: frameHeight)

                    Spacer().frame(height: 18)
                    tabStrip
                    Spacer().frame(height: 16)

                    controls
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: tab)

                    Spacer().frame(height: 24)
                }
                .playerBottomPadding()
            }
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle("Look & Feel")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Preview — the interior switches with the tab

    @AppStorage("playerDesign") private var playerDesignRaw = PlayerDesign.classic.rawValue

    /// Player shows the REAL design gallery preview; Lyrics its sample page;
    /// Theme, Mini and Home all show the home mock — exactly as on Android.
    @ViewBuilder private var preview: some View {
        switch tab {
        case .player:
            // These layouts are authored for the design gallery's frame, which
            // is much wider than the hub's. Lay one out at the gallery's size
            // and scale the whole thing down, rather than cramming a fixed-size
            // layout into a narrower box and watching it spill past the bezel.
            GeometryReader { g in
                let reference: CGFloat = 238
                let scale = g.size.width / reference
                DesignLivePreview(design: PlayerDesign(rawValue: playerDesignRaw) ?? .classic,
                                  player: player)
                    .frame(width: reference, height: g.size.height / max(scale, 0.01))
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            }
        case .lyrics:
            LookFeelLyricsPreview(player: player, position: look.lyricsPosition)
        default:
            // Authored against a ~150×322 screen. The frame shrank when this
            // page gained a mini player, so scale to fit rather than let the
            // nav bar drop off the bottom.
            GeometryReader { g in
                let reference = CGSize(width: 150, height: 322)
                let scale = min(g.size.width / reference.width,
                                g.size.height / reference.height)
                LookFeelThemePreview(player: player)
                    .frame(width: reference.width, height: reference.height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: g.size.width, height: g.size.height,
                           alignment: .topLeading)
            }
        }
    }

    // MARK: Tabs

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LookFeelTab.allCases) { t in
                    let active = t == tab
                    Text(t.title)
                        .font(.system(size: 14, weight: active ? .bold : .medium))
                        .foregroundStyle(active ? palette.onAccent : palette.onSurfaceVariant)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(active ? AnyShapeStyle(palette.accent)
                                           : AnyShapeStyle(palette.surfaceHigh))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { tab = t } }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        switch tab {
        case .theme: LookFeelThemeControls()
        case .player: LookFeelPlayerControls(player: player)
        case .mini: LookFeelMiniControls(player: player)
        case .lyrics: LookFeelLyricsControls()
        case .home: LookFeelHomeControls()
        }
    }
}

/// The phone bezel the preview sits inside — the same construction as the
/// player design gallery, sized by the frame rather than its contents.
struct LookFeelPhoneFrame<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // GeometryReader stays flexible for aspectRatio, and the explicit frame
        // forces the interior to exactly the screen size — an `.overlay` only
        // proposes, and an interior with a wider ideal width spilled the clip.
        GeometryReader { g in
            content()
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.black)
                        .frame(width: 40, height: 11)
                        .padding(.top, 7)
                }
        }
        .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x44454A), Color(hex: 0x26272B), Color(hex: 0x1A1B1E)],
                        startPoint: .top, endPoint: .bottom)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.10), .white.opacity(0.28)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1.4),
            )
            .aspectRatio(9.0 / 19.3, contentMode: .fit)
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }
}

/// Shared card shell for the control groups under the tab strip.
struct LookFeelGroup<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
    }
}

/// One tappable settings row: icon chip, title, current value, chevron.
struct LookFeelRow: View {
    @Environment(\.palette) private var palette
    let icon: String
    let title: String
    var value: String?
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(palette.accent)
                    .frame(width: 38, height: 38)
                    .background(palette.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.onSurface)
                    if let value {
                        Text(value)
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                }
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.onSurface.opacity(0.35))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

/// A row whose trailing control is a switch.
struct LookFeelToggleRow: View {
    @Environment(\.palette) private var palette
    let icon: String
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(palette.accent)
                .frame(width: 38, height: 38)
                .background(palette.accent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).labelsHidden().tint(palette.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(enabled ? 1 : 0.5)
        .disabled(!enabled)
    }
}

/// Hairline between rows in a group.
struct LookFeelDivider: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Divider().overlay(palette.separator).padding(.leading, 66)
    }
}
