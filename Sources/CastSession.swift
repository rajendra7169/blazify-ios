import Foundation
import Network
import SwiftUI

/// Playing to TVs and speakers on the same Wi-Fi with Google Cast: Chromecasts, TVs with one built
/// in, Nest speakers and displays.
///
/// The phone finds each song's stream and hands its link to the plain media player every cast
/// device has; the device fetches it itself, so the music carries on with the phone locked or on
/// a call. The phone keeps the queue and sends each next song when one ends. Songs that exist only
/// on this phone, your own files, cannot be sent, as the device has no way to reach them.
@MainActor
final class CastSession: ObservableObject {
    static let shared = CastSession()
    static let service = "_googlecast._tcp"

    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let model: String?
        /// Speakers and speaker groups have no screen.
        let speaker: Bool
    }

    enum Status: Equatable {
        case idle
        case connecting(Device)
        case connected(Device)
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var status: Status = .idle {
        didSet { Self.isConnectedNow = isConnected }
    }
    /// The same as `isConnected`, readable from anywhere, for the player's checks.
    nonisolated(unsafe) static var isConnectedNow = false
    /// Whether the list of TVs and speakers is open.
    @Published var chooserOpen = false
    /// Why the last thing asked of the device didn't work, for the person.
    @Published var problem: String?

    // What the device says it is doing.
    @Published private(set) var playing = false
    @Published private(set) var loading = false
    private var position: Double = 0
    private var positionSaidAt = Date()
    private var rate: Double = 1

    /// The song has finished on the device: the player moves the queue on.
    var onEnded: (() -> Void)?
    /// The device stopped playing by itself (its own screen, another phone): the player pauses.
    var onStoppedThere: (() -> Void)?

    private var browser: NWBrowser?
    private var link: CastLink?
    private var app: CastLink.App?
    private var mediaSessionId: Int?
    /// The song being sent, so a failed link can be sent again once with a fresh one.
    private var loadingVideoId: String?
    private var retried: Set<String> = []
    private var resend: ((Double) -> Void)?

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    var connectedDevice: Device? {
        if case let .connected(device) = status { return device }
        return nil
    }

    /// Where the song is on the device now, counting on from what it last said.
    var currentPosition: Double {
        guard playing, !loading else { return position }
        return position + Date().timeIntervalSince(positionSaidAt) * rate
    }

    // MARK: - Finding devices

    /// Starts looking for cast devices on the Wi-Fi. The first time, iOS asks whether Blazify may
    /// look on the local network.
    func startLooking() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.service, domain: nil), using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.take(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                // As when the network changed: it starts again the next time the list opens.
                Task { @MainActor in self?.browser = nil }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stopLooking() {
        browser?.cancel()
        browser = nil
    }

    private func take(_ results: Set<NWBrowser.Result>) {
        var found: [Device] = []
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            var text: [String: String] = [:]
            if case let .bonjour(record) = result.metadata { text = record.dictionary }
            func value(_ key: String) -> String? {
                guard let raw = text[key]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
                return raw
            }
            // Bit 0 of the capabilities is a screen.
            let capabilities = value("ca").flatMap { Int($0) } ?? 1
            let model = value("md")
            let speaker = capabilities & 1 == 0 || model == "Google Cast Group"
            found.append(Device(id: name, name: value("fn") ?? name, model: model, speaker: speaker))
        }
        // TVs first, then speakers, each by name.
        devices = found.sorted { ($0.speaker ? 1 : 0, $0.name.lowercased()) < ($1.speaker ? 1 : 0, $1.name.lowercased()) }
    }

    // MARK: - Connecting

    func connect(_ device: Device) async -> Bool {
        if connectedDevice == device { return true }
        disconnect(stopPlaying: false)
        status = .connecting(device)
        problem = nil
        let link = CastLink(serviceName: device.id)
        // CastLink calls both on the main thread.
        link.onMessage = { [weak self] namespace, _, json in
            MainActor.assumeIsolated { self?.heard(namespace, json) }
        }
        link.onClosed = { [weak self, weak link] in
            MainActor.assumeIsolated {
                guard let self, let link, self.link === link else { return }
                self.dropped()
            }
        }
        guard await link.open(), let app = await link.launchMediaPlayer() else {
            link.close()
            if case .connecting = status { status = .idle }
            problem = "Couldn't connect to \(device.name). Check that it's on the same Wi-Fi as this phone."
            return false
        }
        // Someone may have chosen another device while this one was answering.
        guard case let .connecting(chosen) = status, chosen == device else {
            link.close()
            return false
        }
        self.link = link
        self.app = app
        status = .connected(device)
        return true
    }

    /// Ends the connection; with [stopPlaying] the device's player stops too, back to its own screen.
    func disconnect(stopPlaying: Bool) {
        if stopPlaying, let app { link?.stop(app) }
        link?.close()
        link = nil
        app = nil
        mediaSessionId = nil
        loadingVideoId = nil
        resend = nil
        playing = false
        loading = false
        status = .idle
    }

    private func dropped() {
        link = nil
        app = nil
        mediaSessionId = nil
        playing = false
        loading = false
        status = .idle
        problem = "The connection to the TV or speaker was lost."
        onStoppedThere?()
    }

    // MARK: - Playing there

    /// Hands the device a song to play from [startAt] seconds. [fetchLink] finds a fresh stream
    /// link; it is asked again once if the device can't play the first.
    func load(
        videoId: String,
        title: String,
        artist: String,
        artwork: URL?,
        duration: Double,
        startAt: Double,
        fetchLink: @escaping () async -> URL?,
    ) async {
        guard let link, let app else { return }
        loadingVideoId = videoId
        loading = true
        playing = true
        position = startAt
        positionSaidAt = Date()
        resend = { [weak self] at in
            Task { @MainActor in
                await self?.load(videoId: videoId, title: title, artist: artist, artwork: artwork,
                                 duration: duration, startAt: at, fetchLink: fetchLink)
            }
        }
        guard let url = await fetchLink() else {
            guard loadingVideoId == videoId else { return }
            loading = false
            playing = false
            problem = "This song couldn't be sent to the TV or speaker."
            return
        }
        guard loadingVideoId == videoId, self.link === link else { return }
        var metadata: [String: Any] = ["metadataType": 3, "title": title, "artist": artist]
        if let artwork { metadata["images"] = [["url": artwork.absoluteString]] }
        var media: [String: Any] = [
            "contentId": url.absoluteString,
            "contentUrl": url.absoluteString,
            "streamType": "BUFFERED",
            "contentType": "audio/mp4",
            "metadata": metadata,
            "customData": ["videoId": videoId],
        ]
        if duration > 0 { media["duration"] = duration }
        let answer = await link.request(
            CastLink.mediaNS, to: app.transportId,
            body: ["type": "LOAD", "autoplay": true, "currentTime": startAt, "media": media],
            timeout: 25,
        )
        guard loadingVideoId == videoId else { return }
        let type = answer?["type"] as? String
        if answer == nil || type == "LOAD_FAILED" || type == "LOAD_CANCELLED" || type == "INVALID_REQUEST" {
            failedThere(videoId)
            return
        }
        if let answer { mediaStatus(answer) }
    }

    func resume() { control("PLAY") { self.playing = true } }

    func pause() { control("PAUSE") { self.playing = false } }

    func seek(to seconds: Double) {
        guard let link, let app, let mediaSessionId else { return }
        position = max(seconds, 0)
        positionSaidAt = Date()
        link.tell(CastLink.mediaNS, to: app.transportId,
                  body: ["type": "SEEK", "mediaSessionId": mediaSessionId, "currentTime": max(seconds, 0)])
    }

    /// The device's own loudness, 0 to 1.
    func setVolume(_ level: Double) { link?.setVolume(level) }

    private func control(_ type: String, change: () -> Void) {
        guard let link, let app, let mediaSessionId else { return }
        position = currentPosition
        positionSaidAt = Date()
        change()
        link.tell(CastLink.mediaNS, to: app.transportId, body: ["type": type, "mediaSessionId": mediaSessionId])
    }

    // MARK: - What the device says

    private func heard(_ namespace: String, _ json: [String: Any]) {
        if namespace == CastLink.mediaNS, json["type"] as? String == "MEDIA_STATUS" {
            mediaStatus(json)
        }
        if namespace == CastLink.receiverNS, json["type"] as? String == "RECEIVER_STATUS", app != nil,
           CastLink.app(in: json, id: CastLink.mediaPlayerApp) == nil {
            // The media player was closed on the device (its own screen, another phone).
            mediaSessionId = nil
            if playing {
                playing = false
                loading = false
                onStoppedThere?()
            }
        }
    }

    private func mediaStatus(_ json: [String: Any]) {
        guard let status = (json["status"] as? [[String: Any]])?.first else { return }
        if let id = status["mediaSessionId"] as? Int { mediaSessionId = id }
        if let at = status["currentTime"] as? Double {
            position = at
            positionSaidAt = Date()
        }
        if let speed = status["playbackRate"] as? Double, speed > 0 { rate = speed }
        switch status["playerState"] as? String {
        case "PLAYING":
            playing = true
            loading = false
        case "PAUSED":
            playing = false
            loading = false
        case "BUFFERING", "LOADING":
            loading = true
        case "IDLE":
            loading = false
            playing = false
            switch status["idleReason"] as? String {
            case "FINISHED":
                if let id = loadingVideoId { retried.remove(id) }
                loadingVideoId = nil
                onEnded?()
            case "ERROR":
                if let id = loadingVideoId { failedThere(id) }
            default:
                break
            }
        default:
            break
        }
    }

    /// The device couldn't play the link: once with a fresh one, from the same second, then a message.
    private func failedThere(_ videoId: String) {
        loading = false
        playing = false
        if !retried.contains(videoId), let resend {
            retried.insert(videoId)
            resend(position)
            return
        }
        problem = "The TV or speaker couldn't play this song."
    }
}
