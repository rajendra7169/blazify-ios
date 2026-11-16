import Foundation
import SwiftUI
import UIKit

/// Asking for a star, twice per version at most: 10 days after a version is first opened, and
/// once more a month after it. A new version starts the count again.
///
/// - The clock starts when a version is first opened, so it never asks on the day of an update,
///   and an app opened once and left never asks at all.
/// - "Star it" and "Already starred" end it for good, in this version and every later one; the
///   link in About stays for anyone who wants it. Tapping outside only waits for the next ask.
/// - It is never shown while something is playing (the caller checks), and never on a launch
///   that offered a new version.
@MainActor
final class StarPrompt: ObservableObject {
    static let shared = StarPrompt()
    static let repo = "https://github.com/rajendra7169/blazify-ios"

    /// Days after a version is first opened for each of its asks.
    static let askDays: [Double] = [10, 30]

    private enum Key {
        static let version = "starPromptVersion"
        static let since = "starPromptVersionSince"
        static let shown = "starPromptShownThisVersion"
        static let done = "starPromptDone"
    }

    /// True while the card should be on screen.
    @Published var showing = false

    private let defaults = UserDefaults.standard

    private init() {}

    /// Whether an ask is due: [shown] asks of this version so far, the version opened at [since].
    nonisolated static func isDue(now: TimeInterval, since: TimeInterval, shown: Int) -> Bool {
        guard shown < askDays.count else { return false }
        return now >= since + askDays[shown] * 86_400
    }

    /// Records the launch and shows the card if an ask is due.
    func onOpened(somethingIsPlaying: Bool) {
        if defaults.bool(forKey: Key.done) { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let now = Date().timeIntervalSince1970
        if defaults.string(forKey: Key.version) != version {
            // A new version, or the first launch: start its clock, ask nothing yet.
            defaults.set(version, forKey: Key.version)
            defaults.set(now, forKey: Key.since)
            defaults.set(0, forKey: Key.shown)
            return
        }
        if somethingIsPlaying { return }
        let shown = defaults.integer(forKey: Key.shown)
        guard Self.isDue(now: now, since: defaults.double(forKey: Key.since), shown: shown) else { return }
        defaults.set(shown + 1, forKey: Key.shown)
        showing = true
    }

    /// Tapped outside: it waits for this version's next ask, if there is one.
    func dismiss() {
        showing = false
    }

    /// Starred, or already starred. Either way there is nothing left to ask.
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

/// Offering a new version of the app, seen without nagging.
///
/// - The card shows the first time the app is opened after a version is published.
/// - "Later" puts it off for a week; then it shows once more, and that version is never offered
///   on a card again.
/// - "Update" opens the version's page, where its install file is.
@MainActor
final class UpdatePrompt: ObservableObject {
    static let shared = UpdatePrompt()
    static let remindAfterDays = 7.0

    struct Release: Equatable {
        let tag: String
        let version: String
        let page: URL
    }

    private enum Key {
        static let declined = "updateDeclinedVersion"
        static let declinedAt = "updateDeclinedAt"
        static let reminded = "updateRemindedVersion"
    }

    /// The version on offer while its card is on screen.
    @Published var offer: Release?

    private let defaults = UserDefaults.standard
    private var checked = false

    private init() {}

    /// Whether to open the card for [tag]: never put off yet, or put off a week ago or more and
    /// not reminded about since.
    nonisolated static func shouldOffer(tag: String, declinedTag: String?, declinedAt: TimeInterval?,
                                        remindedTag: String?, now: TimeInterval) -> Bool {
        if declinedTag != tag { return true }
        if remindedTag == tag { return false }
        guard let declinedAt else { return false }
        return now >= declinedAt + remindAfterDays * 86_400
    }

    /// Whether [latest] is newer than [current], number by number ("0.10.0" after "0.9.3").
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        let a = latest.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0 ..< max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Asks GitHub for the newest version, once per launch; true when the card is now showing.
    func check() async -> Bool {
        guard !checked else { return offer != nil }
        checked = true
        guard let url = URL(string: "https://api.github.com/repos/rajendra7169/blazify-ios/releases/latest") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String,
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { return false }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard Self.isNewer(version, than: current) else { return false }
        let declined = defaults.string(forKey: Key.declined)
        let declinedAt = defaults.object(forKey: Key.declinedAt) as? Double
        guard Self.shouldOffer(tag: tag, declinedTag: declined, declinedAt: declinedAt,
                               remindedTag: defaults.string(forKey: Key.reminded),
                               now: Date().timeIntervalSince1970)
        else { return false }
        // The reminder counts once it is on screen, so it never comes a third time.
        if declined == tag { defaults.set(tag, forKey: Key.reminded) }
        offer = Release(tag: tag, version: version, page: page)
        return true
    }

    func update() {
        guard let offer else { return }
        self.offer = nil
        UIApplication.shared.open(offer.page)
    }

    /// The first "Later" starts the week before the one reminder; "Later" on the reminder ends it.
    func later() {
        guard let offer else { return }
        self.offer = nil
        if defaults.string(forKey: Key.declined) != offer.tag {
            defaults.set(offer.tag, forKey: Key.declined)
            defaults.set(Date().timeIntervalSince1970, forKey: Key.declinedAt)
        }
    }
}
