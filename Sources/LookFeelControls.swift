import SwiftUI

// MARK: - Theme

/// Theme controls, ported from ThemeControls: four mode
/// circles (System · Light · Dark · Pure black) then the colour palette, where
/// the first swatch is the "dynamic" sentinel that follows the album art.
struct LookFeelThemeControls: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var theme = AppTheme.shared
    @State private var showPicker = false
    @State private var custom = Color.orange

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme mode")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.onSurface)

                HStack(spacing: 16) {
                    modeCircle(.auto, pureBlack: false, icon: "circle.lefthalf.filled", label: "System")
                    Rectangle().fill(palette.separator).frame(width: 1, height: 32)
                    modeCircle(.off, pureBlack: false, label: "Light")
                    modeCircle(.on, pureBlack: false, label: "Dark")
                    modeCircle(.on, pureBlack: true, label: "Black")
                    Spacer(minLength: 0)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Colour palette")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.onSurface)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        dynamicSwatch
                        ForEach(BlazeThemePalette.colors, id: \.name) { entry in
                            swatch(entry.color,
                                   selected: !theme.dynamicTheme && theme.chosenSeed == entry.color)
                        }
                        customSwatch
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                ColorPicker("Custom colour", selection: $custom, supportsOpacity: false)
                    .padding(20)
                    .navigationTitle("Custom colour")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Use") {
                                theme.setDynamicTheme(false)
                                theme.setSeedColor(custom)
                                showPicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.height(220)])
        }
    }

    // MARK: Mode circles

    private func modeCircle(_ mode: DarkMode, pureBlack: Bool,
                            icon: String? = nil, label: String) -> some View {
        let selected = theme.darkMode == mode && (mode != .on || theme.pureBlack == pureBlack)
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(fill(mode: mode, pureBlack: pureBlack))
                    .frame(width: 44, height: 44)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(palette.onSurface)
                }
                Circle()
                    .strokeBorder(selected ? palette.accent : palette.onSurface.opacity(0.18),
                                  lineWidth: selected ? 2.5 : 1)
                    .frame(width: 44, height: 44)
            }
            Text(label)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? palette.accent : palette.onSurfaceVariant)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            theme.setDarkMode(mode)
 // Pure black is only meaningful in dark; clear it otherwise.
            theme.setPureBlack(mode == .on ? pureBlack : false)
        }
    }

    /// Each circle previews the scheme it selects.
    private func fill(mode: DarkMode, pureBlack: Bool) -> Color {
        switch mode {
        case .auto: return palette.surfaceHigh
        case .off: return Color(hex: 0xF4F4F6)
        case .on: return pureBlack ? .black : Color(hex: 0x1C1C1E)
        }
    }

    // MARK: Swatches

    private var dynamicSwatch: some View {
        swatchShell(selected: theme.dynamicTheme) {
            // Sentinel: theming follows the artwork rather than a fixed colour.
            Circle().fill(
                AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                center: .center),
            )
        }
        .onTapGesture { theme.setDynamicTheme(true) }
    }

    private func swatch(_ colour: Color, selected: Bool) -> some View {
        swatchShell(selected: selected) { Circle().fill(colour) }
            .onTapGesture {
                theme.setDynamicTheme(false)
                theme.setSeedColor(colour)
            }
    }

    private var customSwatch: some View {
        swatchShell(selected: false) {
            Circle()
                .fill(palette.surfaceHigh)
                .overlay(Image(systemName: "eyedropper")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.onSurface))
        }
        .onTapGesture {
            custom = theme.seed
            showPicker = true
        }
    }

    private func swatchShell<S: View>(selected: Bool, @ViewBuilder _ content: () -> S) -> some View {
        content()
            .frame(width: 40, height: 40)
            .overlay(
                Circle().strokeBorder(selected ? palette.accent : .clear, lineWidth: 3)
                    .frame(width: 48, height: 48),
            )
            .frame(width: 48, height: 48)
            .contentShape(Circle())
    }
}

/// The palette swatches, minus the dynamic sentinel which is its own swatch.
enum BlazeThemePalette {
    struct Entry { let name: String; let color: Color }

    static let colors: [Entry] = [
        Entry(name: "Blaze", color: Color(hex: 0xFFA726)),
        Entry(name: "Crimson", color: Color(hex: 0xEC5464)),
        Entry(name: "Rose", color: Color(hex: 0xD81B60)),
        Entry(name: "Purple", color: Color(hex: 0x8E24AA)),
        Entry(name: "Deep purple", color: Color(hex: 0x5E35B1)),
        Entry(name: "Indigo", color: Color(hex: 0x3949AB)),
        Entry(name: "Blue", color: Color(hex: 0x1E88E5)),
        Entry(name: "Sky blue", color: Color(hex: 0x039BE5)),
        Entry(name: "Cyan", color: Color(hex: 0x00ACC1)),
        Entry(name: "Teal", color: Color(hex: 0x00897B)),
        Entry(name: "Green", color: Color(hex: 0x43A047)),
        Entry(name: "Light green", color: Color(hex: 0x7CB342)),
        Entry(name: "Lime", color: Color(hex: 0xC0CA33)),
        Entry(name: "Yellow", color: Color(hex: 0xFDD835)),
        Entry(name: "Amber", color: Color(hex: 0xFFB300)),
        Entry(name: "Orange", color: Color(hex: 0xFB8C00)),
        Entry(name: "Deep orange", color: Color(hex: 0xF4511E)),
        Entry(name: "Brown", color: Color(hex: 0x6D4C41)),
        Entry(name: "Grey", color: Color(hex: 0x757575)),
        Entry(name: "Blue grey", color: Color(hex: 0x546E7A)),
    ]
}

// MARK: - Player

struct LookFeelPlayerControls: View {
    @ObservedObject var player: Player
    @ObservedObject private var look = LookFeel.shared
    @AppStorage("playerDesign") private var designRaw = PlayerDesign.classic.rawValue
    @State private var showDesigns = false
    @State private var showSlider = false

    private var design: PlayerDesign { PlayerDesign(rawValue: designRaw) ?? .classic }

    var body: some View {
        LookFeelGroup {
            LookFeelRow(icon: "paintpalette", title: "Player theme", value: design.title) {
                showDesigns = true
            }
            LookFeelDivider()
            LookFeelRow(icon: "slider.horizontal.3", title: "Slider style",
                        value: look.sliderStyle.title(squiggly: look.squigglySlider)) {
                showSlider = true
            }
        }
        .fullScreenCover(isPresented: $showDesigns) {
            PlayerDesignPicker(player: player)
        }
        .sheet(isPresented: $showSlider) {
            SliderStyleSheet()
                .presentationDetents([.height(480)])
        }
    }
}

/// Slider style picker: a 2×2 grid of square
/// tiles — Capsule · Wavy · Slim · Squiggly — each showing its slider live,
/// outlined in the accent when active. Squiggly is WAVY + a flag underneath,
/// but it earns its own tile.
struct SliderStyleSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var look = LookFeel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Slider style")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.top, 20)

            HStack(spacing: 12) {
                tile("Capsule", selected: look.sliderStyle == .capsule) {
                    look.sliderStyle = .capsule; look.squigglySlider = false
                } content: {
                    CapsuleTrack(fraction: 0.2, active: palette.accent,
                                 label: "0:36 / 2:59", compact: true)
                }
                tile("Wavy", selected: look.sliderStyle == .wavy && !look.squigglySlider) {
                    look.sliderStyle = .wavy; look.squigglySlider = false
                } content: {
                    WavyTrack(fraction: 0.5, active: palette.accent,
                              squiggly: false, isPlaying: true, compact: true)
                }
            }
            HStack(spacing: 12) {
                tile("Slim", selected: look.sliderStyle == .slim) {
                    look.sliderStyle = .slim; look.squigglySlider = false
                } content: {
                    SlimTrack(fraction: 0.65, active: palette.accent)
                }
                tile("Squiggly", selected: look.sliderStyle == .wavy && look.squigglySlider) {
                    look.sliderStyle = .wavy; look.squigglySlider = true
                } content: {
                    WavyTrack(fraction: 0.5, active: palette.accent,
                              squiggly: true, isPlaying: true, compact: true)
                }
            }

            Button("Cancel") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.surface)
        .presentationBackground(palette.surface)
    }

    /// One square tile: the live slider above its name, outlined when active.
    private func tile<Content: View>(_ label: String, selected: Bool,
                                     action: @escaping () -> Void,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            content()
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.onSurface)
        }
        .padding(12)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? palette.accent : palette.separator,
                              lineWidth: selected ? 2 : 1),
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

// MARK: - Mini player

struct LookFeelMiniControls: View {
    @Environment(\.palette) private var palette
    @ObservedObject var player: Player
    @ObservedObject private var look = LookFeel.shared
    @State private var showBackground = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mini player design")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.onSurface)
                Text("How the bar above the navigation looks")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            .padding(.horizontal, 16)

            // Two designs per row, each card drawing its design live.
            ForEach(Array(stride(from: 0, to: MiniPlayerDesign.allCases.count, by: 2)), id: \.self) { i in
                HStack(spacing: 12) {
                    designCard(MiniPlayerDesign.allCases[i])
                    if i + 1 < MiniPlayerDesign.allCases.count {
                        designCard(MiniPlayerDesign.allCases[i + 1])
                    }
                }
                .padding(.horizontal, 16)
            }

            LookFeelGroup {
                LookFeelRow(icon: "square.stack.3d.up",
                            title: "Background style",
                            value: look.miniPlayerBackground.title) {
                    // FLAT paints from the theme, so the choice does nothing there.
                    if look.miniPlayerDesign.usesArtBackground { showBackground = true }
                }
                .opacity(look.miniPlayerDesign.usesArtBackground ? 1 : 0.5)
            }
        }
        .confirmationDialog("Background style", isPresented: $showBackground,
                            titleVisibility: .visible) {
            ForEach(MiniPlayerBackground.allCases) { style in
                Button(style.title) { look.miniPlayerBackground = style }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func designCard(_ design: MiniPlayerDesign) -> some View {
        let selected = look.miniPlayerDesign == design
        return VStack(spacing: 8) {
            MiniPlayerPreviewBar(player: player, design: design,
                                 background: look.miniPlayerBackground)
                .allowsHitTesting(false)
            Text(design.title)
                .font(.system(size: 13, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? palette.accent : palette.onSurface)
            Text(design.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(palette.onSurfaceVariant)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? palette.accent : palette.separator,
                              lineWidth: selected ? 2 : 1),
        )
        .contentShape(Rectangle())
        .onTapGesture { look.miniPlayerDesign = design }
    }
}

// MARK: - Lyrics

struct LookFeelLyricsControls: View {
    @ObservedObject private var look = LookFeel.shared
    @State private var showPosition = false

    var body: some View {
        LookFeelGroup {
            LookFeelRow(icon: "text.alignleft", title: "Lyrics text position",
                        value: look.lyricsPosition.title) {
                showPosition = true
            }
        }
        .confirmationDialog("Lyrics text position", isPresented: $showPosition,
                            titleVisibility: .visible) {
            ForEach(LyricsPosition.allCases) { position in
                Button(position.title) { look.lyricsPosition = position }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Home

struct LookFeelHomeControls: View {
    @ObservedObject private var look = LookFeel.shared
    @State private var showDefaultTab = false
    @State private var showGrid = false
    @State private var showNavStyle = false

    var body: some View {
        LookFeelGroup {
            LookFeelRow(icon: "house", title: "Default open tab",
                        value: look.defaultTab.title) { showDefaultTab = true }
            LookFeelDivider()
            LookFeelRow(icon: "square.grid.2x2", title: "Grid cell size",
                        value: look.gridItemSize.title) { showGrid = true }
            LookFeelDivider()
            LookFeelRow(icon: "rectangle.bottomthird.inset.filled", title: "Nav bar style",
                        value: look.navBarStyle.title) { showNavStyle = true }
            LookFeelDivider()
            LookFeelToggleRow(icon: "rectangle.compress.vertical", title: "Slim nav bar",
                              subtitle: "Hide the labels under the icons",
                              isOn: $look.slimNavBar)
            LookFeelDivider()
            LookFeelToggleRow(icon: "hand.wave", title: "Show home greeting",
                              subtitle: "The welcome card at the top of Home",
                              isOn: $look.showHomeGreeting)
            LookFeelDivider()
            LookFeelToggleRow(icon: "magnifyingglass", title: "Show home search bar",
                              subtitle: "The search pill under the greeting",
                              isOn: $look.showHomeSearchBar)
        }
        .confirmationDialog("Default open tab", isPresented: $showDefaultTab,
                            titleVisibility: .visible) {
            ForEach(DefaultTab.allCases) { t in
                Button(t.title) { look.defaultTab = t }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Grid cell size", isPresented: $showGrid, titleVisibility: .visible) {
            ForEach(GridItemSize.allCases) { size in
                Button(size.title) { look.gridItemSize = size }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Nav bar style", isPresented: $showNavStyle, titleVisibility: .visible) {
            ForEach(NavBarStyle.allCases) { style in
                Button(style.title) { look.navBarStyle = style }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
