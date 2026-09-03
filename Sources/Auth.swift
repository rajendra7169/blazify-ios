import Foundation
import CryptoKit
import Combine

/// YouTube account session, ported from Blazify the login:
/// a captured Google cookie + `SAPISIDHASH` auth on WEB_REMIX requests.
final class Auth: ObservableObject {
    static let shared = Auth()

    // UI-facing state.
    @Published private(set) var isLoggedIn = false
    @Published private(set) var accountName: String?
    @Published private(set) var accountEmail: String?

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
        isLoggedIn = !(cookie ?? "").isEmpty
    }

    private enum Keys {
        static let cookie = "yt_cookie"
        static let visitor = "yt_visitorData"
        static let dataSync = "yt_dataSyncId"
        static let name = "yt_accountName"
        static let email = "yt_accountEmail"
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
        guard isLoggedIn, (accountName ?? "").isEmpty else { return }
        Task { @MainActor in
            guard let info = await YouTube.accountInfo() else { return }
            self.accountName = info.name
            self.accountEmail = info.email
            self.defaults.set(info.name, forKey: Keys.name)
            self.defaults.set(info.email, forKey: Keys.email)
        }
    }

    /// Validate a freshly captured cookie via account_menu, then persist on success.
    func signIn(cookie: String, visitorData: String?, dataSyncId: String?) async -> Bool {
        self.cookie = cookie
        if let visitorData, !visitorData.isEmpty { self.visitorData = visitorData }
        self.dataSyncId = dataSyncId

        guard let info = await YouTube.accountInfo() else {
            self.cookie = nil   // roll back — invalid/expired
            return false
        }

        await MainActor.run {
            self.accountName = info.name
            self.accountEmail = info.email
            self.isLoggedIn = true
        }
        Keychain.set(cookie, for: Keys.cookie)
        defaults.set(self.visitorData, forKey: Keys.visitor)
        defaults.set(dataSyncId, forKey: Keys.dataSync)
        defaults.set(info.name, forKey: Keys.name)
        defaults.set(info.email, forKey: Keys.email)
        return true
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

    func signOut() {
        cookie = nil
        dataSyncId = nil
        Keychain.set(nil, for: Keys.cookie)
        for key in [Keys.dataSync, Keys.name, Keys.email] { defaults.removeObject(forKey: key) }
        Task { @MainActor in
            self.accountName = nil
            self.accountEmail = nil
            self.isLoggedIn = false
        }
    }
}
