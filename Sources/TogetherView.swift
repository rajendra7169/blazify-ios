import SwiftUI
import UIKit

/// Listen Together: host a room or join one by code, then everyone follows the
/// host's playback. Works with Blazify on Android — same server, same protocol.
struct TogetherView: View {
    @ObservedObject private var lt = ListenTogether.shared
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.dismiss) private var dismiss

    @State private var joinCode = ""
    @State private var name = ListenTogether.shared.username

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if lt.state == .inRoom {
                        roomView
                    } else {
                        lobbyView
                    }
                }
                .padding(20)
            }
            .background(theme.scaffold.ignoresSafeArea())
            .navigationTitle("Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Blaze.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Lobby

    private var lobbyView: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 40)).foregroundStyle(Blaze.amber)
                Text("Listen with friends")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Text("Everyone hears the same song at the same time. Works with Blazify on Android too.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)

            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your name").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .tint(Blaze.amber)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onChange(of: name) { lt.saveUsername(name) }
                }
            }

            Button {
                lt.saveUsername(name)
                lt.createRoom()
            } label: {
                Text("Start a room")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Blaze.gradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Join a room").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    HStack(spacing: 10) {
                        TextField("Room code", text: $joinCode)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .tint(Blaze.amber)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            lt.saveUsername(name)
                            lt.joinRoom(code: joinCode)
                        } label: {
                            Text("Join")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 20).frame(height: 44)
                                .background(Blaze.amber)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            if case .connecting = lt.state {
                ProgressView().tint(Blaze.amber)
            }
            if case .failed(let message) = lt.state {
                Text(message)
                    .font(.system(size: 13)).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: In a room

    private var roomView: some View {
        VStack(spacing: 18) {
            card {
                VStack(spacing: 10) {
                    Text(lt.isHost ? "You're hosting" : "In the room")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(lt.roomCode)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .foregroundStyle(Blaze.amber)
                    Button {
                        UIPasteboard.general.string = lt.roomCode
                    } label: {
                        Label("Copy code", systemImage: "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    if lt.isHost {
                        Text("Share this code — what you play, they hear.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if !lt.pendingJoins.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Wants to join").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        ForEach(lt.pendingJoins) { member in
                            HStack {
                                Text(member.name).foregroundStyle(.white).lineLimit(1)
                                Spacer()
                                Button("Allow") { lt.approve(member) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Blaze.amber)
                                Button("Deny") { lt.reject(member) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                }
            }

            card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Listening (\(lt.members.count))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    ForEach(lt.members) { member in
                        HStack(spacing: 10) {
                            Image(systemName: member.isHost ? "crown.fill" : "person.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(member.isHost ? Blaze.amber : .white.opacity(0.6))
                            Text(member.name).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }

            Button { lt.leave() } label: {
                Text("Leave room")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .overlay(Capsule().stroke(.red.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
