import Foundation
import SwiftUI
import UIKit

/// Asking for a star: once a day after the first launch, then weekly for two
/// months, and then never again.
///
/// The rules matter more than the feature. A prompt that keeps returning is how
/// an app earns a bad word from somebody who actually liked it, so:
///
/// - The clock starts on first launch and the first ask is a day later, so an
///   app opened once and abandoned never asks at all.
/// - Later means later: a week each time, and after the last of them it stops
///   on its own rather than carrying on.
/// - No thanks means never, with no route back into the schedule.
/// - It is never shown while something is playing, which the caller enforces,
///   because interrupting music to ask a favour is worse than not asking.
///
/// The link in About stays regardless, for anyone who says no and changes their
/// mind.
@MainActor
final class StarPrompt: ObservableObject {
    static let shared = StarPrompt()

    static let repo = "https://github.com/rajendra7169/blazify-ios"

    private let hoursBeforeFirstAsk: TimeInterval = 24 * 3_600
    private let gapBetweenAsks: TimeInterval = 7 * 86_400

    /// The first ask a day in, then one a week: the last lands just short of
    /// two months.
    private let maxAsks = 9

    private enum Key {
        static let nextAt = "starPromptNextAt"
        static let asks = "starPromptAsks"
        static let done = "starPromptDone"
    }

    /// True while the prompt should be on screen.
    @Published var showing = false

    private let defaults = UserDefaults.standard

    private init() {}

    /// Records the launch and shows the prompt if it is due. Safe to call on
    /// every launch: the schedule only moves when an ask is actually shown.
    func onOpened(somethingIsPlaying: Bool) {
        if defaults.bool(forKey: Key.done) || somethingIsPlaying { return }

        let asks = defaults.integer(forKey: Key.asks)
        guard asks < maxAsks else { return }

        let nextAt = defaults.double(forKey: Key.nextAt)
        guard nextAt > 0 else {
            // First launch. Start the clock and ask nothing yet — an app that
            // begs for a star before it has played a song has not earned one.
            defaults.set(Date().timeIntervalSince1970 + hoursBeforeFirstAsk, forKey: Key.nextAt)
            return
        }
        guard Date().timeIntervalSince1970 >= nextAt else { return }

        defaults.set(asks + 1, forKey: Key.asks)
        // A week until the next, and after the last one there is no next.
        if asks + 1 >= maxAsks {
            defaults.set(true, forKey: Key.done)
        } else {
            defaults.set(Date().timeIntervalSince1970 + gapBetweenAsks, forKey: Key.nextAt)
        }
        showing = true
    }

    /// Later. It comes back in a week, until the last one.
    func dismiss() {
        showing = false
    }

    /// Starred, or declined. Either way there is nothing left to ask.
    func stop() {
        showing = false
        defaults.set(true, forKey: Key.done)
    }

    func open() {
        stop()
        if let url = URL(string: Self.repo) {
            UIApplication.shared.open(url)
        }
    }
}
