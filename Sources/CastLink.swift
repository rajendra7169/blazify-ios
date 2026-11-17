import Foundation
import Network

/// A connection to one Google Cast device, a Chromecast, a TV with one built in, a Nest speaker
/// or display, in the protocol those devices speak: JSON messages in named channels over a
/// secure socket on the local network. It starts apps on the device (here only the plain media
/// player every cast device has), sends them commands and passes on what the device says.
///
/// Everything it holds is touched on its own queue; what it hears is handed to the main thread.
final class CastLink: @unchecked Sendable {
    /// An app running on the device, and its address there for messages.
    struct App: Equatable {
        let sessionId: String
        let transportId: String
    }

    static let sender = "sender-0"
    static let receiver = "receiver-0"
    static let connectionNS = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeatNS = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let receiverNS = "urn:x-cast:com.google.cast.receiver"
    static let mediaNS = "urn:x-cast:com.google.cast.media"
    /// The plain media player every cast device has, for sound sent as a link.
    static let mediaPlayerApp = "CC1AD845"

    /// Every message the device sends: its channel, who sent it and its JSON. On the main thread.
    var onMessage: ((String, String, [String: Any]) -> Void)?
    /// The connection ended, from either side. On the main thread, once.
    var onClosed: (() -> Void)?

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "blazify.cast.link")
    private var framer = CastFramer()
    private var nextRequestId = 0
    private var waiting: [Int: ([String: Any]?) -> Void] = [:]
    private var watchers: [UUID: ([String: Any], String) -> Bool] = [:]
    private var heartbeat: DispatchSourceTimer?
    private var ended = false

    /// A device found on the network, reached by its Bonjour name.
    init(serviceName: String) {
        let tls = NWProtocolTLS.Options()
        // Cast devices sign their connections themselves; no public authority vouches for them.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 8
        let endpoint = NWEndpoint.service(name: serviceName, type: CastSession.service, domain: "local.", interface: nil)
        connection = NWConnection(to: endpoint, using: NWParameters(tls: tls, tcp: tcp))
    }

    /// Connects and asks how the device is; false when it can't be reached.
    func open() async -> Bool {
        let opened: Bool = await withCheckedContinuation { continuation in
            let answer = OneAnswer(continuation)
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    answer.give(true)
                case .failed, .cancelled:
                    answer.give(false)
                    self.finish()
                case .waiting:
                    // Not reachable as things stand (a local network not allowed, a device gone).
                    answer.give(false)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 10) { answer.give(false) }
        }
        guard opened else {
            close()
            return false
        }
        queue.async { self.receive() }
        send(Self.connectionNS, to: Self.receiver, json: ["type": "CONNECT"])
        startHeartbeat()
        guard await request(Self.receiverNS, to: Self.receiver, body: ["type": "GET_STATUS"]) != nil else {
            close()
            return false
        }
        return true
    }

    /// Starts the media player on the device, or finds it already running, and connects to it;
    /// nil when the device refuses or does not answer.
    func launchMediaPlayer() async -> App? {
        if let status = await request(Self.receiverNS, to: Self.receiver, body: ["type": "GET_STATUS"]),
           let app = Self.app(in: status, id: Self.mediaPlayerApp) {
            send(Self.connectionNS, to: app.transportId, json: ["type": "CONNECT"])
            return app
        }
        // Launching answers with the device's status once the app is up, which can take a while.
        let launched = await waitFor(timeout: 25, sending: { id in
            (Self.receiverNS, Self.receiver, ["type": "LAUNCH", "appId": Self.mediaPlayerApp, "requestId": id])
        }) { json, _ in
            let type = json["type"] as? String
            return type == "LAUNCH_ERROR" || (type == "RECEIVER_STATUS" && Self.app(in: json, id: Self.mediaPlayerApp) != nil)
        }
        guard let launched, let app = Self.app(in: launched, id: Self.mediaPlayerApp) else { return nil }
        send(Self.connectionNS, to: app.transportId, json: ["type": "CONNECT"])
        return app
    }

    /// Sends [body] with a request number and waits for the answer carrying the same number.
    func request(_ namespace: String, to destination: String, body: [String: Any], timeout: TimeInterval = 8) async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !self.ended else {
                    continuation.resume(returning: nil)
                    return
                }
                self.nextRequestId += 1
                let id = self.nextRequestId
                let answer = OneAnswer(continuation)
                self.waiting[id] = { json in answer.give(json) }
                var message = body
                message["requestId"] = id
                self.write(namespace, to: destination, json: message)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.waiting.removeValue(forKey: id)?(nil)
                }
            }
        }
    }

    /// Sends [body] with a request number, without waiting for the answer.
    func tell(_ namespace: String, to destination: String, body: [String: Any]) {
        queue.async {
            self.nextRequestId += 1
            var message = body
            message["requestId"] = self.nextRequestId
            self.write(namespace, to: destination, json: message)
        }
    }

    /// The device's own loudness, 0 to 1.
    func setVolume(_ level: Double) {
        tell(Self.receiverNS, to: Self.receiver, body: ["type": "SET_VOLUME", "volume": ["level": min(max(level, 0), 1)]])
    }

    /// Stops [app] on the device, back to its own screen.
    func stop(_ app: App) {
        tell(Self.receiverNS, to: Self.receiver, body: ["type": "STOP", "sessionId": app.sessionId])
    }

    func close() {
        queue.async { self.finish() }
    }

    // MARK: - Inside, on the queue

    /// Waits for the first message [matches] accepts, after sending what [sending] builds with a
    /// fresh request number; nil on a timeout.
    private func waitFor(
        timeout: TimeInterval,
        sending: @escaping (Int) -> (String, String, [String: Any]),
        matches: @escaping ([String: Any], String) -> Bool,
    ) async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !self.ended else {
                    continuation.resume(returning: nil)
                    return
                }
                let key = UUID()
                let answer = OneAnswer(continuation)
                self.watchers[key] = { json, namespace in
                    guard matches(json, namespace) else { return false }
                    self.watchers.removeValue(forKey: key)
                    answer.give(json)
                    return true
                }
                self.nextRequestId += 1
                let (namespace, destination, body) = sending(self.nextRequestId)
                self.write(namespace, to: destination, json: body)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.watchers.removeValue(forKey: key)
                    answer.give(nil)
                }
            }
        }
    }

    private func send(_ namespace: String, to destination: String, json: [String: Any]) {
        queue.async { self.write(namespace, to: destination, json: json) }
    }

    private func write(_ namespace: String, to destination: String, json: [String: Any]) {
        guard !ended,
              let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8)
        else { return }
        let frame = CastWire.encode(CastMessage(source: Self.sender, destination: destination, namespace: namespace, payload: text))
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.queue.async { self?.finish() } }
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                for message in self.framer.feed(data) { self.take(message) }
            }
            if complete || error != nil {
                self.finish()
            } else if !self.ended {
                self.receive()
            }
        }
    }

    private func take(_ message: CastMessage) {
        guard let data = message.payload.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        let type = json["type"] as? String
        if message.namespace == Self.heartbeatNS, type == "PING" {
            write(Self.heartbeatNS, to: message.source, json: ["type": "PONG"])
            return
        }
        if message.namespace == Self.connectionNS, type == "CLOSE", message.source == Self.receiver {
            finish()
            return
        }
        if let id = json["requestId"] as? Int, id != 0, let answer = waiting.removeValue(forKey: id) {
            answer(json)
        }
        for (_, watcher) in watchers where watcher(json, message.namespace) { break }
        let namespace = message.namespace
        let source = message.source
        DispatchQueue.main.async { self.onMessage?(namespace, source, json) }
    }

    private func startHeartbeat() {
        queue.async {
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in
                self?.write(Self.heartbeatNS, to: Self.receiver, json: ["type": "PING"])
            }
            timer.resume()
            self.heartbeat = timer
        }
    }

    private func finish() {
        guard !ended else { return }
        ended = true
        heartbeat?.cancel()
        heartbeat = nil
        connection.cancel()
        let pending = waiting.values
        waiting.removeAll()
        pending.forEach { $0(nil) }
        DispatchQueue.main.async { self.onClosed?() }
    }

    /// The app [id] in a receiver status, if it is running.
    static func app(in json: [String: Any], id: String) -> App? {
        guard let status = json["status"] as? [String: Any],
              let apps = status["applications"] as? [[String: Any]],
              let app = apps.first(where: { $0["appId"] as? String == id }),
              let session = app["sessionId"] as? String,
              let transport = app["transportId"] as? String
        else { return nil }
        return App(sessionId: session, transportId: transport)
    }
}

/// Resumes a continuation once, whichever of several callbacks gets there first; the rest are
/// ignored. A lock rather than a captured flag, as those callbacks can arrive on any thread.
private final class OneAnswer<T>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func give(_ value: T) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
    }
}
