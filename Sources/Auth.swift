import Foundation
import CryptoKit
import Combine

/// One account this phone has been signed in to: everything needed to be
/// signed in to it again without typing a password.
struct SavedAccount: Codable, Identifiable, Equatable {
    var cookie: String
    var visitorData: String?
    var dataSyncId: String?
    var name: String
    var email: String?
    var photo: String?

    /// One Google account with two channels is two entries, and the same
    /// channel is only ever one.
    var id: String { Self.key(email: email, dataSyncId: dataSyncId, name: name) }

    static func key(email: String?, dataSyncId: String?, name: String?) -> String {
        let channel = (dataSyncId ?? "").components(separatedBy: "||").first ?? ""
        return "\(email ?? "")|\(channel.isEmpty ? (name ?? "") : channel)"
    }
}

/// YouTube account session, ported from Blazify the login:
/// a captured Google cookie + `SAPISIDHASH` auth on WEB_REMIX requests.
///
/// Only one account is in use at a time, and the rest of the app reads only
/// that one. The others this phone has been signed in to wait in
/// `savedAccounts`; changing account writes another one into the same places
/// the app has always read, and bumps `generation` so every screen showing the
/// account's own things loads them again.
final class Auth: ObservableObject {
    static let shared = Auth()

    // UI-facing state.
    @Published private(set) var isLoggedIn = false
    @Published private(set) var accountName: String?
    @Published private(set) var accountEmail: String?
    /// The signed-in channel's picture. Kept beside the name so Home and
    /// settings can show a face instead of a silhouette.
    @Published private(set) var accountPhoto: String?
    /// Every account signed in to on this phone, the one in use included.
    @Published private(set) var savedAccounts: [SavedAccount] = []
    /// Goes up by one whenever the account in use changes — signing in,
    /// signing out, or switching. Screens that load the account's library key
    /// their loading on this rather than on `isLoggedIn`, which stays true
    /// from one account to the next and so would never reload.
    @Published private(set) var generation = 0

    // Credentials (read from any thread by YouTube.post()).
    private(set) var cookie: String?
    private(set) var visitorData: String?
    private(set) var dataSyncId: String?

    private let defaults = UserDefaults.standard

    private init() {
        cookie = Keychain.get(Keys.cookie)
        visitorData = defaults.string(forKey: Keys.visitor)
        dataSyncId = defaults.string(forKey: Keys.dataSync)
        accountName = defaults.string(forKey: Keys.name)
        accountEmail = defaults.string(forKey: Keys.email)
        accountPhoto = defaults.string(forKey: Keys.photo)
        isLoggedIn = !(cookie ?? "").isEmpty
        savedAccounts = Auth.readSaved()
    }

    private enum Keys {
        static let cookie = "yt_cookie"
        static let visitor = "yt_visitorData"
        static let dataSync = "yt_dataSyncId"
        static let name = "yt_accountName"
        static let email = "yt_accountEmail"
        static let photo = "yt_accountPhoto"
        /// The saved accounts, cookies and all — so the keychain, not defaults.
        static let saved = "yt_savedAccounts"
    }

    private var cookieMap: [String: String] {
        guard let cookie else { return [:] }
        var map: [String: String] = [:]
        for pair in cookie.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            map[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces)
        }
        return map
    }

    /// The APISID used to sign requests (SAPISID, or its 3P/1P mirror).
    private var sapisid: String? {
        let map = cookieMap
        return map["SAPISID"] ?? map["__Secure-3PAPISID"] ?? map["__Secure-1PAPISID"]
    }

    /// Auth headers for a WEB_REMIX music request. Empty when logged out.
    func headers() -> [String: String] {
        guard let cookie, let sapisid else { return [:] }
        let ts = Int(Date().timeIntervalSince1970)
        let digest = Insecure.SHA1.hash(data: Data("\(ts) \(sapisid) https://music.youtube.com".utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return [
            "Cookie": cookie,
            "Authorization": "SAPISIDHASH \(ts)_\(hash)",
            "X-Origin": "https://music.youtube.com",
            "X-Goog-AuthUser": "0",
        ]
    }

    /// The channel signed-in requests are made on behalf of. A Google account
    /// can own several channels, each with its own playlists and likes, and
    /// without this every request would be answered as the default one.
    var channelId: String? {
        guard let dataSyncId, !dataSyncId.isEmpty else { return nil }
        return dataSyncId
    }

    /// The saved-list key of the account in use, or nil when signed out.
    var currentAccountKey: String? {
        guard isLoggedIn else { return nil }
        return SavedAccount.key(email: accountEmail, dataSyncId: dataSyncId, name: accountName)
    }

    /// The saved accounts other than the one in use — all of them when
    /// signed out.
    var otherAccounts: [SavedAccount] {
        let current = currentAccountKey
        return savedAccounts.filter { $0.id != current }
    }

    /// Fill in a name we are signed in without.
    ///
    /// A session restored from the keychain counts as signed in because the
    /// cookie is there, whether or not the name was ever stored beside it: an
    /// older build did not save one, and a single failed account_menu call left
    /// it empty for good with nothing to try again. The result was somebody
    /// signed in and greeted as Guest.
    ///
    /// Deliberately not called from `init`. Asking would reach back through
    /// `Auth.shared` while that is still being constructed.
    func refreshAccountNameIfMissing() {
        // The picture counts as missing too: sessions signed in before there
        // was one to store have a name and no face.
        guard isLoggedIn, (accountName ?? "").isEmpty || (accountPhoto ?? "").isEmpty else { return }
        Task { @MainActor in
            guard let info = await YouTube.accountInfo() else { return }
            self.accountName = info.name
            self.accountEmail = info.email
            self.accountPhoto = info.photo
            self.defaults.set(info.name, forKey: Keys.name)
            self.defaults.set(info.email, forKey: Keys.email)
            self.defaults.set(info.photo, forKey: Keys.photo)
            self.rememberCurrent()
        }
    }

    // MARK: Signing in

    /// The credentials requests are made with, kept so a sign-in that comes to
    /// nothing can put back exactly what was in use before it began.
    struct Identity {
        let cookie: String?
        let visitorData: String?
        let dataSyncId: String?
    }

    var identity: Identity {
        Identity(cookie: cookie, visitorData: visitorData, dataSyncId: dataSyncId)
    }

    /// Put back the credentials from before a sign-in or switch began. Nothing
    /// saved has changed by then, so this is all there is to undo.
    func restore(_ identity: Identity) {
        cookie = identity.cookie
        visitorData = identity.visitorData
        dataSyncId = identity.dataSyncId
    }

    /// Step one of signing in: ask whether the cookie the sign-in page handed
    /// over really is an account, as that account, within 20 seconds.
    ///
    /// Nothing is saved yet. On no answer the credentials in use before are
    /// put back, so backing out of adding an account leaves the one in use
    /// working. On an answer they stay in place for the channel list to be
    /// asked with, until `finishSignIn` or `restore`.
    func check(cookie: String, visitorData: String?, dataSyncId: String?) async -> YouTube.AccountInfo? {
        // The account being left stays on the list, to switch back to.
        await MainActor.run { self.rememberCurrent() }
        let before = identity
        self.cookie = cookie
        // A visitor id from another account is not this one's; with none,
        // requests ask the catalogue for a fresh one.
        self.visitorData = (visitorData ?? "").isEmpty ? nil : visitorData
        self.dataSyncId = dataSyncId

        let info = await withTimeLimit(seconds: 20) { await YouTube.accountInfo() }
        if info == nil { restore(before) }
        return info
    }

    /// Step two: make the checked sign-in the account in use, and save it.
    /// `channel` is the one picked when the account has several; without one
    /// the channel Google chose stays.
    ///
    /// Call on the main thread — it changes what the screens show.
    func finishSignIn(cookie: String, visitorData: String?, dataSyncId: String?,
                      info: YouTube.AccountInfo, channel: YouTube.AccountChannel?) {
        self.cookie = cookie
        self.visitorData = (visitorData ?? "").isEmpty ? nil : visitorData
        self.dataSyncId = channel?.id ?? dataSyncId
        accountName = channel?.name ?? info.name
        accountEmail = info.email
        accountPhoto = channel?.photo ?? info.photo
        isLoggedIn = true
        persistCurrent()
        rememberCurrent()
        accountChanged()
    }

    // MARK: Several accounts

    /// Make a saved account the one in use.
    ///
    /// The account is asked first whether it still answers, within 20
    /// seconds: a sign-in kept for months can have been ended from Google's
    /// side, and finding that out after the switch would leave somebody signed
    /// out of the account they were happily using. False means it didn't
    /// answer, and then nothing has changed.
    func use(_ account: SavedAccount) async -> Bool {
        await MainActor.run { self.rememberCurrent() }
        let before = identity
        cookie = account.cookie
        visitorData = (account.visitorData ?? "").isEmpty ? nil : account.visitorData
        dataSyncId = account.dataSyncId

        let answer = await withTimeLimit(seconds: 20) { await YouTube.accountInfo() }
        guard let info = answer else {
            restore(before)
            return false
        }
        await MainActor.run {
            // The saved name and picture are the channel's own; the answer
            // fills in only what was never saved.
            self.accountName = account.name.isEmpty ? info.name : account.name
            self.accountEmail = account.email ?? info.email
            self.accountPhoto = account.photo ?? info.photo
            self.isLoggedIn = true
            self.persistCurrent()
            self.rememberCurrent()
            self.accountChanged()
        }
        return true
    }

    /// The account in use, added to the saved list or brought up to date in
    /// it. Call on the main thread.
    func rememberCurrent() {
        let map = cookieMap
        guard isLoggedIn, let cookie, !cookie.isEmpty,
              map["SAPISID"] != nil || map["__Secure-3PAPISID"] != nil
        else { return }
        let current = SavedAccount(cookie: cookie, visitorData: visitorData, dataSyncId: dataSyncId,
                                   name: accountName ?? "", email: accountEmail, photo: accountPhoto)
        var list = savedAccounts
        if let at = list.firstIndex(where: { $0.id == current.id }) {
            var kept = current
            // A picture we had stays until there is a newer one.
            if (kept.photo ?? "").isEmpty { kept.photo = list[at].photo }
            list[at] = kept
        } else {
            list.append(current)
        }
        guard list != savedAccounts else { return }
        savedAccounts = list
        Auth.writeSaved(list)
    }

    /// Take an account off this phone. Call on the main thread.
    func forget(_ account: SavedAccount) {
        savedAccounts.removeAll { $0.id == account.id }
        Auth.writeSaved(savedAccounts)
    }

    private static func readSaved() -> [SavedAccount] {
        guard let text = Keychain.get(Keys.saved), let data = text.data(using: .utf8),
              let list = try? JSONDecoder().decode([SavedAccount].self, from: data)
        else { return [] }
        return list
    }

    private static func writeSaved(_ list: [SavedAccount]) {
        guard !list.isEmpty, let data = try? JSONEncoder().encode(list) else {
            Keychain.set(nil, for: Keys.saved)
            return
        }
        Keychain.set(String(data: data, encoding: .utf8), for: Keys.saved)
    }

    /// The account in use, written where the next launch reads it.
    private func persistCurrent() {
        Keychain.set(cookie, for: Keys.cookie)
        defaults.set(visitorData, forKey: Keys.visitor)
        defaults.set(dataSyncId, forKey: Keys.dataSync)
        defaults.set(accountName, forKey: Keys.name)
        defaults.set(accountEmail, forKey: Keys.email)
        defaults.set(accountPhoto, forKey: Keys.photo)
    }

    /// Tell every screen the account in use is now a different one.
    private func accountChanged() {
        generation += 1
        NotificationCenter.default.post(name: .blazifyAccountChanged, object: nil)
    }

 /// The credential blob we show behind "tap to show token" — your own
    /// session, on your own device.
    func tokenBlob() -> String {
        """
        ***INNERTUBE COOKIE*** =\(cookie ?? "")
        ***VISITOR DATA*** =\(visitorData ?? "")
        ***DATASYNC ID*** =\(dataSyncId ?? "")
        ***ACCOUNT NAME*** =\(accountName ?? "")
        ***ACCOUNT EMAIL*** =\(accountEmail ?? "")
        """
    }

    /// Signing out of the account in use also takes it off the saved list:
    /// that is what signing out asks. Any other saved accounts stay.
    func signOut() {
        let leaving = currentAccountKey
        cookie = nil
        dataSyncId = nil
        Keychain.set(nil, for: Keys.cookie)
        for key in [Keys.dataSync, Keys.name, Keys.email, Keys.photo] { defaults.removeObject(forKey: key) }
        Task { @MainActor in
            self.accountName = nil
            self.accountEmail = nil
            self.accountPhoto = nil
            self.isLoggedIn = false
            if let leaving {
                self.savedAccounts.removeAll { $0.id == leaving }
                Auth.writeSaved(self.savedAccounts)
            }
            self.accountChanged()
        }
    }
}

extension Notification.Name {
    /// Posted when the account in use changes, so what was synced for the last
    /// one can make way for this one's.
    static let blazifyAccountChanged = Notification.Name("blazifyAccountChanged")
}

/// Whatever answers first: the work, or the end of the time limit (as nil).
///
/// The work is called off when the time runs out, but nothing waits for it to
/// stop. An answer that never comes therefore cannot hold up a sign-in or a
/// switch — the screen moves on either way.
func withTimeLimit<T>(seconds: Double, _ work: @escaping () async -> T?) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let answer = FirstAnswer<T>(continuation)
        let worker = Task {
            let value = await work()
            answer.give(value)
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            worker.cancel()
            answer.give(nil)
        }
    }
}

/// Resumes its continuation once, with whichever value arrives first.
private final class FirstAnswer<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func give(_ value: T?) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
    }
}
