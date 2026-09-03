import Foundation
import SwiftUI
import UIKit

/// Asking for a star, at most three times, and then never again.
///
/// The rules matter more than the feature. A prompt that keeps returning is how
/// an app earns a bad word from somebody who actually liked it, so:
///
/// - Days are counted by opening the app, not by the calendar since install.
///   Somebody who installed it and forgot has not used it for three days.
/// - Later means later, and the gap grows: three days, then a fortnight, then a
///   month, after which it stops on its own.
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

    private let daysBeforeFirstAsk = 3
    private let laterGaps: [TimeInterval] = [15 * 86_400, 30 * 86_400]
    private let maxAsks = 3

    private enum Key {
        static let daysUsed = "starPromptDaysUsed"
        static let lastDay = "starPromptLastDay"
        static let nextAt = "starPromptNextAt"
        static let asks = "starPromptAsks"
        static let done = "starPromptDone"
    }

    /// True while the prompt should be on screen.
    @Published var showing = false

    private let defaults = UserDefaults.standard

    private init() {}

    /// Records that the app was opened today, and shows the prompt if it is due.
    /// Safe to call on every launch: the day counter moves at most once per
    /// calendar day.
    func onOpened(somethingIsPlaying: Bool) {
        if defaults.bool(forKey: Key.done) || somethingIsPlaying { return }

        let today = ISO8601DateFormatter.dayOnly.string(from: Date())
        var daysUsed = defaults.integer(forKey: Key.daysUsed)
        if defaults.string(forKey: Key.lastDay) != today {
            daysUsed += 1
            defaults.set(today, forKey: Key.lastDay)
            defaults.set(daysUsed, forKey: Key.daysUsed)
        }

        guard daysUsed >= daysBeforeFirstAsk else { return }

        let asks = defaults.integer(forKey: Key.asks)
        guard asks < maxAsks else { return }
        guard Date().timeIntervalSince1970 >= defaults.double(forKey: Key.nextAt) else { return }

        defaults.set(asks + 1, forKey: Key.asks)
        // The next gap is longer, and after the last one there is no next.
        if let gap = laterGaps.indices.contains(asks) ? laterGaps[asks] : nil {
            defaults.set(Date().timeIntervalSince1970 + gap, forKey: Key.nextAt)
        } else {
            defaults.set(true, forKey: Key.done)
        }
        showing = true
    }

    /// Later. It comes back once, further away, and then not at all.
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

private extension ISO8601DateFormatter {
    /// Just the calendar day, so "have they opened it today" is a string compare.
    static let dayOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
