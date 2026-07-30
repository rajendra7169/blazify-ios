import SwiftUI
import UIKit

/// Blaze Together, ported from ListenTogetherScreen.kt: header, connection
/// status, the room card with its shareable code, connected users, pending join
/// requests, the join/create form and the room settings.
///
/// Everyone follows the host's playback. Same server and protocol as Blazify on
/// Android, so an iPhone and an Android phone can share a room.
struct TogetherView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var lt = ListenTogether.shared
    @Environment(\.dismiss) private var dismiss

    @State private var joinCode = ""
    @State private var name = ListenTogether.shared.username
    @State private var copied = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    connectionStatus

                    if lt.state == .inRoom {
                        roomCard
                        if !lt.pendingJoins.isEmpty { joinRequests }
                        connectedUsers
                        leaveButton
                    } else {
                        joinCreate
                        backgroundNote
                    }

                    settingsLink
                }
                .padding(20)
                .playerBottomPadding()
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Blaze Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(palette.accent)
                }
            }
            .navigationDestination(isPresented: $showSettings) { TogetherSettingsView() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(palette.accent)
            Text("Listen Together")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.onSurface)
            Text("Listen to music with your friends in real time. Create a room to host, or join an existing room with a code.")
                .font(.system(size: 13))
                .foregroundStyle(palette.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    // MARK: Connection

    private var connectionStatus: some View {
        let (label, colour): (String, Color) = {
            switch lt.state {
            case .inRoom: return ("Connected", .green)
            case .connecting: return ("Connecting…", palette.accent)
            case .failed(let why): return (why.isEmpty ? "Connection error" : why, .red)
            case .idle: return ("Disconnected", palette.onSurfaceVariant)
            }
        }()

        return card {
            HStack(spacing: 12) {
                Circle().fill(colour).frame(width: 10, height: 10)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if lt.state == .inRoom {
                    Text(lt.isHost ? "You are the host" : "You are a guest")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }
        }
    }

    // MARK: Room

    private var roomCard: some View {
        card {
            VStack(spacing: 12) {
                Text("Room code")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)

                Text(lt.roomCode)
                    .font(.system(size: 34, weight: .black, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(palette.accent)

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = lt.roomCode
                        copied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copied = false
                        }
                    } label: {
                        pill(copied ? "Copied" : "Copy code", icon: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.plain)

                    Button {
                        share("Join my Blazify room with code \(lt.roomCode)")
                    } label: {
                        pill("Share", icon: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var connectedUsers: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("In the room · \(lt.members.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)

                ForEach(lt.members) { member in
                    HStack(spacing: 12) {
                        avatar(member.name)
                        Text(member.name)
                            .font(.system(size: 15))
                            .foregroundStyle(palette.onSurface)
                            .lineLimit(1)
                        if member.isHost {
                            Text("HOST")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(palette.onAccent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(palette.accent)
                                .clipShape(Capsule())
                        }
                        Spacer(minLength: 0)
                        // Only the host can throw someone out and keep them out.
                        if lt.isHost, !member.isHost {
                            Menu {
                                Button("Block \(member.name)", role: .destructive) {
                                    lt.reject(member)
                                    lt.block(member.name)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }

    private var joinRequests: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Join requests")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)

                ForEach(lt.pendingJoins) { member in
                    HStack(spacing: 12) {
                        avatar(member.name)
                        Text(member.name)
                            .font(.system(size: 15))
                            .foregroundStyle(palette.onSurface)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button { lt.approve(member) } label: {
                            Image(systemName: "checkmark").foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        Button { lt.reject(member) } label: {
                            Image(systemName: "xmark").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var leaveButton: some View {
        Button { lt.leave() } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Leave room").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.red)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Join / create

    private var joinCreate: some View {
        VStack(spacing: 14) {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your name")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .foregroundStyle(palette.onSurface)
                        .tint(palette.accent)
                        .padding(.vertical, 10).padding(.horizontal, 14)
                        .background(palette.onSurface.opacity(0.06))
                        .clipShape(Capsule())
                        .onChange(of: name) { lt.saveUsername(name) }
                }
            }

            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Create room")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.onSurface)
                    Text("Create a room and share the code with your friends.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.onSurfaceVariant)
                    Button {
                        lt.saveUsername(name)
                        lt.createRoom()
                    } label: {
                        Text("Create")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(palette.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Join existing room")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.onSurface)
                    TextField("Enter a room code", text: $joinCode)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .foregroundStyle(palette.onSurface)
                        .tint(palette.accent)
                        .padding(.vertical, 10).padding(.horizontal, 14)
                        .background(palette.onSurface.opacity(0.06))
                        .clipShape(Capsule())
                    Button {
                        lt.saveUsername(name)
                        lt.joinRoom(code: joinCode)
                    } label: {
                        Text("Join")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(palette.onSurface.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var backgroundNote: some View {
        Text("When you're connected but not in a room, Listen Together disconnects after 30 minutes in the background to save battery.")
            .font(.system(size: 11.5))
            .foregroundStyle(palette.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    private var settingsLink: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "gearshape")
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Together settings")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.onSurface)
                    Text("Server, auto-approve, sync volume")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.onSurface.opacity(0.35))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Bits

    private func avatar(_ name: String) -> some View {
        Circle()
            .fill(palette.accent.opacity(0.2))
            .frame(width: 36, height: 36)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.accent),
            )
    }

    private func pill(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13))
            Text(text).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(palette.onSurface)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(palette.onSurface.opacity(0.08))
        .clipShape(Capsule())
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func share(_ text: String) {
        let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?.rootViewController else { return }
        // We're inside a sheet, so present from whatever is on top.
        (root.presentedViewController ?? root).present(sheet, animated: true)
    }
}

/// Listen Together settings, ported from ListenTogetherSettings.kt — reachable
/// both from the Together sheet and from Settings > Connections.
struct TogetherSettingsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var lt = ListenTogether.shared

    @AppStorage("ltAutoApproveJoins") private var autoApproveJoins = false
    @AppStorage("ltServerURL") private var serverURL = ListenTogether.defaultServer

    @State private var name = ListenTogether.shared.username
    @State private var showLogs = false
    @State private var showBlocked = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                group {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                        Text(lt.state == .inRoom
                             ? "The username can't be changed while you're in a room."
                             : "How you appear to everyone else in the room.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
                        TextField("Username", text: $name)
                            .textFieldStyle(.plain)
                            .foregroundStyle(palette.onSurface)
                            .tint(palette.accent)
                            .disabled(lt.state == .inRoom)
                            .padding(.vertical, 10).padding(.horizontal, 14)
                            .background(palette.onSurface.opacity(0.06))
                            .clipShape(Capsule())
                            .onChange(of: name) { lt.saveUsername(name) }
                    }
                    .padding(16)
                }

                group {
                    toggle("Auto-approve join requests",
                           "Let people in without reviewing each request.",
                           $autoApproveJoins)
                }

                group {
                    row("Blocked users",
                        lt.blocked.isEmpty ? "No blocked users" : "\(lt.blocked.count) blocked") {
                        showBlocked = true
                    }
                    Divider().overlay(palette.separator)
                    row("Connection logs",
                        lt.logs.isEmpty ? "No logs yet" : "\(lt.logs.count) events") {
                        showLogs = true
                    }
                }

                group {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server URL")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                        Text("Must match your friends' server, or you won't see each other's rooms.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
                        TextField("Server", text: $serverURL)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(palette.onSurface)
                            .tint(palette.accent)
                            .padding(.vertical, 10).padding(.horizontal, 14)
                            .background(palette.onSurface.opacity(0.06))
                            .clipShape(Capsule())
                        Button("Reset to default") { serverURL = ListenTogether.defaultServer }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .padding(16)
                }
            }
            .padding(16)
            .playerBottomPadding()
        }
        .background(palette.scaffold.ignoresSafeArea())
        .navigationTitle("Together settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogs) { TogetherLogsView() }
        .sheet(isPresented: $showBlocked) { TogetherBlockedView() }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ title: String, _ value: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.onSurface)
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.onSurface.opacity(0.35))
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ title: String, _ subtitle: String,
                        _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.onSurface)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: binding).labelsHidden().tint(palette.accent)
        }
        .padding(16)
    }
}

/// Connection events, with a copy button — Android's log viewer.
struct TogetherLogsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lt = ListenTogether.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                if lt.logs.isEmpty {
                    Text("No logs yet")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .padding(.top, 60)
                } else {
                    Text(lt.logs.joined(separator: "\n"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.onSurface)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Connection logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Copy") { UIPasteboard.general.string = lt.logs.joined(separator: "\n") }
                        Button("Clear", role: .destructive) { lt.clearLogs() }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
    }
}

/// The block list, with swipe-to-unblock.
struct TogetherBlockedView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lt = ListenTogether.shared

    var body: some View {
        NavigationStack {
            Group {
                if lt.blocked.isEmpty {
                    Text("No blocked users")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(lt.blocked, id: \.self) { name in
                            Text(name).foregroundStyle(palette.onSurface)
                                .listRowBackground(palette.surface)
                        }
                        .onDelete { offsets in
                            offsets.map { lt.blocked[$0] }.forEach(lt.unblock)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Blocked users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
