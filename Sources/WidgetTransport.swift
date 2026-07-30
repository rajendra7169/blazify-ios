import AppIntents
import Foundation
import WidgetKit

/// The widget's transport buttons. Compiled into both targets: the widget needs
/// the intent types to put in a `Button(intent:)`, the app needs the receiver.
///
/// These deliberately do NOT go through the App Group. A tap has to reach a
/// process that is already running and already holds the AVPlayer, and Darwin
/// notifications do that with no entitlement at all — so the controls keep
/// working even if the shared container never gets signed. The trade is that
/// they carry no payload and only reach a live process, which is fine: the app
/// is alive for the whole of the case that matters, because it's playing audio.
enum WidgetTransport: String, CaseIterable {
    case playPause, next, previous

    private var notification: String { "com.rajendra.blazifyplayer.transport.\(rawValue)" }

    func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notification as CFString),
            nil, nil, true)
    }

    /// Called once by the app at launch. The observer is a C callback, so it
    /// can't capture context — it posts a normal NotificationCenter name that
    /// the app side can listen to like anything else.
    static func startListening() {
        for command in allCases {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                nil,
                { _, _, name, _, _ in
                    guard let cf = name?.rawValue else { return }
                    let raw = cf as String
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .blazifyWidgetTransport,
                                                        object: nil,
                                                        userInfo: ["command": raw])
                    }
                },
                command.notification as CFString,
                nil,
                .deliverImmediately)
        }
    }

    /// Turn a received Darwin name back into a command.
    static func command(from raw: String) -> WidgetTransport? {
        allCases.first { raw.hasSuffix($0.rawValue) }
    }
}

extension Notification.Name {
    static let blazifyWidgetTransport = Notification.Name("blazify.widget.transport")
}

// MARK: - Intents behind the buttons

/// `Button(intent:)` runs this inside the widget extension, which is why the
/// body is only a signal: the extension has no player of its own.
struct WidgetPlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or pause"
    /// Staying out of the app is the whole point of an interactive widget.
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        WidgetTransport.playPause.post()
        // The app writes a fresh snapshot when the state actually changes; this
        // just gets the glyph to flip without waiting on the system's own
        // reload cadence.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct WidgetNextIntent: AppIntent {
    static var title: LocalizedStringResource = "Next song"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        WidgetTransport.next.post()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct WidgetPreviousIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous song"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        WidgetTransport.previous.post()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
