import SwiftUI

/// Shared chrome for the settings sheets. Each sheet is its own presentation, so
/// the root's mini player is covered by every one of them — this puts it back,
/// on every page, and routes a tap to the root's full player.
struct SettingsMiniPlayer: ViewModifier {
    @ObservedObject var player: Player
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.current != nil {
                MiniPlayerView(player: player) {
                    // The full player belongs to the root, so this sheet has to
                    // step aside or it would open behind us.
                    dismiss()
                    player.showFullPlayer = true
                }
                .padding(.bottom, 6)
            }
        }
    }
}

extension View {
    /// Adds the mini player to a settings page.
    func settingsMiniPlayer(_ player: Player) -> some View {
        modifier(SettingsMiniPlayer(player: player))
    }
}

// MARK: - Shared rows

/// A titled card of rows, the shape every settings page uses.
struct SettingsGroup<Content: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct SettingsDivider: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Divider().overlay(palette.onSurface.opacity(0.06)).padding(.leading, 56)
    }
}

/// A row that opens something, with the current value as its subtitle.
struct SettingsLink: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let title: String
    var subtitle: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SettingsIcon(symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.onSurface)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant.opacity(0.7))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsToggle: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let title: String
    var subtitle: String = ""
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.onSurface)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).labelsHidden().tint(palette.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// A row whose value is a slider, for the settings Android puts in a dialog but
/// that read better inline (speed, crossfade length).
struct SettingsSlider: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    let readout: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                SettingsIcon(symbol)
                Text(title).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.onSurface)
                Spacer(minLength: 8)
                Text(readout(value))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
            }
            Group {
                if step > 0 {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
            }
            .tint(palette.accent)
            .padding(.leading, 40)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct SettingsIcon: View {
    @Environment(\.palette) private var palette
    let symbol: String
    init(_ symbol: String) { self.symbol = symbol }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15))
            .foregroundStyle(palette.accent)
            .frame(width: 26)
    }
}

/// The page shell every settings screen shares: scaffold colour, inline title
/// and consistent padding.
struct SettingsPage<Content: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content() }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
