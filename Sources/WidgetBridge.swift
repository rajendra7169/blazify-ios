import Combine
import Foundation
import UIKit
import WidgetKit

/// The app's half of the widget conversation: it publishes what's playing, and
/// it acts on the buttons the widget sends back.
///
/// Not actor-isolated on purpose: it's called straight from the player's
/// now-playing update, which runs wherever AVFoundation happens to call back
/// from. Anything that touches the player hops to main itself.
final class WidgetBridge {
    static let shared = WidgetBridge()

    private weak var player: Player?
    private var observer: AnyCancellable?
    /// What the widget was last *told*, minus the parts that move on their own.
    /// A widget reload is a metered resource — a few dozen a day — so we only
    /// spend one when something the widget can't work out for itself changed.
    private var lastKey = ""

    private init() {}

    func start(player: Player) {
        self.player = player
        WidgetTransport.startListening()
        observer = NotificationCenter.default
            .publisher(for: .blazifyWidgetTransport)
            .sink { [weak self] note in
                guard let raw = note.userInfo?["command"] as? String,
                      let command = WidgetTransport.command(from: raw) else { return }
                self?.apply(command)
            }
    }

    private func apply(_ command: WidgetTransport) {
        DispatchQueue.main.async { self.run(command) }
    }

    private func run(_ command: WidgetTransport) {
        guard let player, player.hasTrack else { return }
        switch command {
        case .playPause: player.toggle()
        case .next: _ = player.next()
        case .previous: player.prev()
        }
    }

    /// Called from the same place that updates the lock screen, so the widget
    /// and Control Centre can never disagree about what's playing.
    func publish(title: String, artist: String, videoId: String,
                 isPlaying: Bool, position: Double, duration: Double) {
        let snapshot = SharedTrack(title: title, artist: artist, videoId: videoId,
                                   isPlaying: isPlaying, duration: duration,
                                   position: position, stamp: Date())
        NowPlayingShare.write(snapshot)

        // Position is deliberately out of the key: the widget extrapolates it
        // from the stamp, so a moving playhead is not a reason to redraw.
        let key = "\(videoId)|\(isPlaying)|\(Int(duration))"
        guard key != lastKey else { return }
        lastKey = key
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The record label. Written whenever the player decodes art anyway, so
    /// there's no second download for the widget's sake.
    func publish(artwork: UIImage?) {
        NowPlayingShare.writeArtwork(artwork)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
