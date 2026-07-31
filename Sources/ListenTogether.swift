import Foundation
import Combine

/// Listen Together — protobuf over a binary WebSocket, speaking the same
/// protocol as Blazify Android so iOS and Android can share a room.
///
/// Only the host broadcasts; guests follow. Every client streams its own audio
/// from YouTube, so this synchronises *control*, not audio.
@MainActor
final class ListenTogether: ObservableObject {
    static let shared = ListenTogether()

    struct Member: Identifiable, Equatable {
        let id: String
        let name: String
        var isHost: Bool
    }

    enum State: Equatable { case idle, connecting, inRoom, failed(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var roomCode = ""
    @Published private(set) var isHost = false
    @Published private(set) var members: [Member] = []
    @Published private(set) var pendingJoins: [Member] = []
    @Published var username = UserDefaults.standard.string(forKey: "ltUsername") ?? "Blazify listener"
    /// Connection events, newest last — Android's "View logs".
    @Published private(set) var logs: [String] = []
    /// Names you've blocked from your rooms.
    @Published private(set) var blocked: [String] =
        UserDefaults.standard.stringArray(forKey: "ltBlocked") ?? []

    /// Set by the app so incoming host actions can drive playback.
    var onRemote: ((RemoteAction) -> Void)?

    enum RemoteAction {
        case play(position: Double)
        case pause(position: Double)
        case seek(position: Double)
        case changeTrack(Track, position: Double)
    }

    private var task: URLSessionWebSocketTask?
    private var userId = ""
    private var revision: UInt64 = 0
    /// Guard so following a host action doesn't echo straight back out.
    private var applyingRemote = false

    /// Blazify Android's default room server.
    static let defaultServer = "wss://metroserverx.meowery.eu/ws"

    /// Whatever the Together settings say, falling back to the default.
    private var serverURL: URL {
        let saved = UserDefaults.standard.string(forKey: "ltServerURL") ?? ""
        return URL(string: saved.isEmpty ? Self.defaultServer : saved)
            ?? URL(string: Self.defaultServer)!
    }

    /// Host-side automation from Together settings.
    private var autoApproveJoins: Bool {
        UserDefaults.standard.bool(forKey: "ltAutoApproveJoins")
    }

    // MARK: Logs

    /// Timestamped, capped — enough to debug a room without growing forever.
    func log(_ message: String) {
        let stamp = Self.logFormatter.string(from: Date())
        logs.append("[\(stamp)] \(message)")
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
    }

    func clearLogs() { logs = [] }

    private static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: Blocking

    func block(_ name: String) {
        guard !name.isEmpty, !blocked.contains(name) else { return }
        blocked.append(name)
        UserDefaults.standard.set(blocked, forKey: "ltBlocked")
        log("Blocked \(name)")
    }

    func unblock(_ name: String) {
        blocked.removeAll { $0 == name }
        UserDefaults.standard.set(blocked, forKey: "ltBlocked")
    }

    // MARK: Connection

    private func connect() {
        guard task == nil else { return }
        var request = URLRequest(url: serverURL)
        request.setValue("com.blazify.music", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: request)
        task?.resume()
        log("Connecting to \(serverURL.absoluteString)")
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                Task { @MainActor in
                    if self.state != .idle { self.state = .failed(error.localizedDescription) }
                    self.log("Disconnected: \(error.localizedDescription)")
                    self.task = nil
                }
            case .success(let message):
                if case .data(let data) = message {
                    Task { @MainActor in self.handle(data) }
                }
                // Re-arm on the main actor: this callback runs on the socket's
                // own queue, and receive() is main-actor isolated.
                Task { @MainActor in self.receive() }
            }
        }
    }

    private func send(_ type: String, _ payload: Data) {
        let envelope = Proto.field(1, type) + Proto.field(2, payload)
        task?.send(.data(envelope)) { _ in }
    }

    // MARK: Rooms

    func createRoom() {
        state = .connecting
        isHost = true
        connect()
        log("Creating a room as \(username)")
        send("create_room", Proto.field(1, username))
    }

    func joinRoom(code: String) {
        let clean = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard !clean.isEmpty else { return }
        state = .connecting
        isHost = false
        connect()
        log("Joining room \(clean)")
        send("join_room", Proto.field(1, clean) + Proto.field(2, username))
    }

    func leave() {
        log("Left the room")
        send("leave_room", Data())
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .idle
        roomCode = ""
        members = []
        pendingJoins = []
        isHost = false
    }

    func approve(_ member: Member) {
        send("approve_join", Proto.field(1, member.id))
        pendingJoins.removeAll { $0.id == member.id }
        members.append(member)
    }

    func reject(_ member: Member) {
        send("reject_join", Proto.field(1, member.id))
        pendingJoins.removeAll { $0.id == member.id }
    }

    func saveUsername(_ name: String) {
        username = name
        UserDefaults.standard.set(name, forKey: "ltUsername")
    }

    // MARK: Host broadcasts

    func broadcastPlay(position: Double) { action("play", position: position) }
    func broadcastPause(position: Double) { action("pause", position: position) }
    func broadcastSeek(position: Double) { action("seek", position: position) }

    func broadcastTrack(_ track: Track, position: Double) {
        guard isHost, state == .inRoom, !applyingRemote else { return }
        // A file that only exists on this phone can't be resolved by anyone
        // else in the room — sending its id would just break their playback.
        guard !LocalMusic.isLocal(track.videoId) else { return }
        revision += 1
        let info = Proto.field(1, track.videoId)
            + Proto.field(2, track.title)
            + Proto.field(3, track.artist)
            + Proto.field(5, int: Int64(track.duration * 1000))
            + Proto.field(6, track.thumbnail)
        let payload = Proto.field(1, "change_track")
            + Proto.field(2, track.videoId)
            + Proto.field(3, int: Int64(position * 1000))
            + Proto.field(4, info)
            + Proto.field(10, int: Int64(revision))
        send("playback_action", payload)
    }

    private func action(_ name: String, position: Double) {
        guard isHost, state == .inRoom, !applyingRemote else { return }
        revision += 1
        let payload = Proto.field(1, name)
            + Proto.field(3, int: Int64(position * 1000))
            + Proto.field(10, int: Int64(revision))
        send("playback_action", payload)
    }

    // MARK: Incoming

    private func handle(_ data: Data) {
        let envelope = Proto.parse(data)
        let type = Proto.string(envelope, 1)
        var payload = (envelope[2]?.first as? Data) ?? Data()
        if Proto.bool(envelope, 3), let plain = Proto.gunzip(payload) { payload = plain }
        let f = Proto.parse(payload)

        switch type {
        case "room_created":
            roomCode = Proto.string(f, 1)
            userId = Proto.string(f, 2)
            state = .inRoom
            members = [Member(id: userId, name: username, isHost: true)]

        case "join_approved":
            roomCode = Proto.string(f, 1)
            userId = Proto.string(f, 2)
            state = .inRoom
            if let room = Proto.message(f, 4) { applyRoomState(room) }

        case "join_rejected":
            state = .failed(Proto.string(f, 1).isEmpty ? "Join rejected" : Proto.string(f, 1))

        case "join_request":
            let member = Member(id: Proto.string(f, 1), name: Proto.string(f, 2), isHost: false)
            guard !member.id.isEmpty else { break }
            log("Join request from \(member.name)")
            if blocked.contains(member.name) {
                log("Rejected \(member.name) — blocked")
                reject(member)
                break
            }
            // Hosts can opt out of vetting every request (Together settings).
            if autoApproveJoins {
                approve(member)
            } else {
                pendingJoins.append(member)
            }

        case "user_joined":
            let member = Member(id: Proto.string(f, 1), name: Proto.string(f, 2), isHost: false)
            if !member.id.isEmpty, !members.contains(where: { $0.id == member.id }) {
                members.append(member)
            }

        case "user_left":
            let id = Proto.string(f, 1)
            members.removeAll { $0.id == id }

        case "host_changed":
            let newHost = Proto.string(f, 1)
            isHost = (newHost == userId)
            members = members.map { Member(id: $0.id, name: $0.name, isHost: $0.id == newHost) }

        case "kicked":
            leave()

        case "error":
            state = .failed(Proto.string(f, 2))

        case "sync_playback":
            applyPlayback(f)

        case "sync_state":
            applySyncState(f)

        default:
            break
        }
    }

    private func applyRoomState(_ room: [Int: [Any]]) {
        let hostId = Proto.string(room, 2)
        members = Proto.messages(room, 3).map {
            Member(id: Proto.string($0, 1), name: Proto.string($0, 2),
                   isHost: Proto.string($0, 1) == hostId)
        }
        if let track = Proto.message(room, 4) {
            deliverTrack(track, positionMs: Proto.int(room, 6), playing: Proto.bool(room, 5))
        }
    }

    private func applySyncState(_ f: [Int: [Any]]) {
        if let track = Proto.message(f, 1) {
            deliverTrack(track, positionMs: Proto.int(f, 3), playing: Proto.bool(f, 2))
        }
    }

    /// A host action arrived — apply it without echoing it back.
    private func applyPlayback(_ f: [Int: [Any]]) {
        guard !isHost else { return }
        let action = Proto.string(f, 1)
        let position = Double(Proto.int(f, 3)) / 1000

        applyingRemote = true
        defer { applyingRemote = false }

        switch action {
        case "play": onRemote?(.play(position: position))
        case "pause": onRemote?(.pause(position: position))
        case "seek": onRemote?(.seek(position: position))
        case "change_track":
            if let info = Proto.message(f, 4) {
                deliverTrack(info, positionMs: Proto.int(f, 3), playing: true)
            }
        default: break
        }
    }

    private func deliverTrack(_ info: [Int: [Any]], positionMs: Int64, playing: Bool) {
        guard !isHost else { return }
        let track = Track(
            videoId: Proto.string(info, 1),
            title: Proto.string(info, 2),
            artist: Proto.string(info, 3),
            thumbnail: Proto.string(info, 6),
            duration: Double(Proto.int(info, 5)) / 1000,
        )
        guard !track.videoId.isEmpty else { return }
        applyingRemote = true
        defer { applyingRemote = false }
        onRemote?(.changeTrack(track, position: Double(positionMs) / 1000))
    }
}
