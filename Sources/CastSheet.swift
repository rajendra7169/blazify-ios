import SwiftUI

/// The Cast key in the player's bottom row: amber while songs go to a TV or speaker, and the
/// sheet to choose one, with AirPlay and Bluetooth at its foot.
struct CastButton: View {
    @ObservedObject var player: Player
    @ObservedObject private var session = CastSession.shared
    var tint: Color = .white.opacity(0.85)
    var activeTint: Color = Blaze.amber
    var iconSize: CGFloat = 22
    var labelSize: CGFloat = 11
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            VStack(spacing: 4) {
                Image(systemName: session.isConnected ? "tv.and.mediabox.fill" : "tv.and.mediabox")
                    .font(.system(size: iconSize))
                    .frame(height: 26)
                Text(session.connectedDevice?.name ?? "Cast")
                    .font(.system(size: labelSize))
                    .lineLimit(1)
            }
            .foregroundStyle(session.isConnected ? activeTint : tint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.connectedDevice.map { "Playing on \($0.name)" } ?? "Cast to a TV or speaker")
        .sheet(isPresented: $open) {
            CastSheet(player: player)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// The TVs and speakers on this Wi-Fi, to play on one, and AirPlay and Bluetooth below them.
struct CastSheet: View {
    @ObservedObject var player: Player
    @ObservedObject private var session = CastSession.shared
    @Environment(\.dismiss) private var dismiss
    @State private var volume = 0.5

    var body: some View {
        NavigationStack {
            List {
                if let device = session.connectedDevice {
                    Section {
                        HStack(spacing: 14) {
                            deviceIcon(device, active: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).font(.body.weight(.semibold))
                                Text("Playing here").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                            Slider(value: $volume, in: 0 ... 1) { editing in
                                if !editing { session.setVolume(volume) }
                            }
                            .tint(Blaze.amber)
                            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                        }
                        Button(role: .destructive) {
                            let at = session.currentPosition
                            session.disconnect(stopPlaying: true)
                            player.castStopped(at: at)
                        } label: {
                            Label("Stop casting", systemImage: "xmark.circle")
                        }
                    }
                }

                Section {
                    if session.devices.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Looking for TVs and speakers on this Wi-Fi…")
                                .foregroundStyle(.secondary)
                        }
                        Text("They show up here when they're on the same Wi-Fi as this phone. If iOS asked about finding devices on your local network, Blazify needs that allowed: Settings › Privacy & Security › Local Network.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.devices) { device in
                        Button {
                            choose(device)
                        } label: {
                            HStack(spacing: 14) {
                                deviceIcon(device, active: session.connectedDevice == device)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name).foregroundStyle(.primary)
                                    if let model = device.model {
                                        Text(model).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if case let .connecting(chosen) = session.status, chosen == device {
                                    ProgressView()
                                } else if session.connectedDevice == device {
                                    Image(systemName: "checkmark").foregroundStyle(Blaze.amber)
                                }
                            }
                        }
                        .disabled(session.connectedDevice == device)
                    }
                } header: {
                    Text("TVs and speakers")
                } footer: {
                    if let problem = session.problem {
                        Text(problem).foregroundStyle(.red)
                    }
                }

                Section {
                    HStack(spacing: 14) {
                        RoutePicker(tint: UIColor.label, activeTint: UIColor(Blaze.amber))
                            .frame(width: 30, height: 30)
                        Text("AirPlay and Bluetooth")
                        Spacer()
                    }
                } footer: {
                    Text("For AirPlay speakers, Apple TV, headphones and Bluetooth speakers.")
                }
            }
            .navigationTitle("Play on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { session.startLooking() }
        .onDisappear {
            if !session.isConnected { session.stopLooking() }
        }
    }

    private func choose(_ device: CastSession.Device) {
        let wasCasting = session.isConnected
        let at = session.currentPosition
        Task {
            if wasCasting { player.castStopped(at: at) }
            if await session.connect(device) {
                player.castStarted()
                dismiss()
            }
        }
    }

    private func deviceIcon(_ device: CastSession.Device, active: Bool) -> some View {
        Image(systemName: device.speaker ? "hifispeaker.fill" : "tv.fill")
            .font(.system(size: 20))
            .foregroundStyle(active ? Blaze.amber : .secondary)
            .frame(width: 30)
    }
}
