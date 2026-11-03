import SwiftUI
import WebKit

/// Google / YouTube Music sign-in in a WKWebView.
/// On landing back on music.youtube.com with a valid session we capture the cookie
/// + visitorData + dataSyncId, validate via account_menu, and persist.
///
/// Until the very end nothing is saved: the account in use before stays the
/// account in use, so Close at any point — even while "Signing in…" shows —
/// leaves the app exactly as it was.
struct LoginView: View {
    /// Start from a sign-in page that knows no one. Adding another account
    /// needs this: a page still signed in hands straight back the account
    /// already in use.
    var freshStart = false

    @Environment(\.dismiss) private var dismiss
    @State private var validating = false
    @State private var failed = false
    /// Until Google's first page has drawn. Without this the sheet was an empty
    /// page for as long as the network took, which reads as the app having hung.
    @State private var pageLoading = true
    /// Why Google's page didn't arrive, said rather than left blank.
    @State private var loadError: String?
    /// Bumped by Try again: a new web view, starting the sign-in afresh.
    @State private var attempt = 0
    /// The finishing work, kept so Close can call it off.
    @State private var work: Task<Void, Never>?
    /// What was in use before finishing began, put back if it is called off.
    @State private var before: Auth.Identity?
    /// A checked sign-in whose account has several channels, waiting on which.
    @State private var channelChoice: PendingSignIn?

    /// A sign-in that has been checked and waits only on the channel.
    private struct PendingSignIn {
        let cookie: String
        let visitorData: String?
        let dataSyncId: String?
        let info: YouTube.AccountInfo
        let channels: [YouTube.AccountChannel]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LoginWebView(freshStart: freshStart,
                             onLoading: { pageLoading = $0 },
                             onFailure: { loadError = $0 }) { cookie, visitor, dataSyncId in
                    finish(cookie: cookie, visitor: visitor, dataSyncId: dataSyncId)
                }
                .id(attempt)
                .ignoresSafeArea(edges: .bottom)

                if let loadError, !validating {
                    Blaze.surface.ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Couldn't open Google sign-in")
                            .font(.system(size: 17, weight: .semibold))
                        Text(loadError)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            self.loadError = nil
                            pageLoading = true
                            attempt += 1
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Blaze.amber)
                        .padding(.top, 4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                } else if pageLoading, !validating {
                    Blaze.surface.ignoresSafeArea()
                    BlazeLoader(size: 64, tint: Blaze.amber)
                }

                // Once the sign-in is in hand the website has nothing more to
                // offer and only invites tapping around in it, so it is covered
                // until the account is ready. Close still calls it all off.
                if validating {
                    Blaze.surface.ignoresSafeArea()
                    VStack(spacing: 16) {
                        BlazeLoader(size: 72, tint: Blaze.amber)
                        Text("Signing in…")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                }

                if let choice = channelChoice {
                    channelChooser(choice)
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        cancelSignIn()
                        dismiss()
                    }
                    .tint(Blaze.amber)
                }
            }
            .alert("Sign-in failed", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Couldn't verify that account. Please try again.")
            }
        }
        .preferredColorScheme(.dark)
        // However the sheet goes — Close, or a swipe down — a sign-in still
        // being finished is called off and the account in use put back.
        .onDisappear { cancelSignIn() }
    }

    // MARK: Finishing

    /// The page has handed over a sign-in: check it, ask which channel when
    /// there is a choice, then make it the account in use. Every network step
    /// has a time limit, so this always ends — in the new account, in the
    /// failure alert, or back where it started.
    private func finish(cookie: String, visitor: String?, dataSyncId: String?) {
        guard !validating else { return }
        validating = true
        let snapshot = Auth.shared.identity
        before = snapshot
        work = Task {
            let info = await Auth.shared.check(cookie: cookie, visitorData: visitor, dataSyncId: dataSyncId)
            guard let info else {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    before = nil
                    work = nil
                    validating = false
                    failed = true
                }
                return
            }
            if Task.isCancelled {
                Auth.shared.restore(snapshot)
                return
            }

            // More than one channel on the account: which one is a real
            // question, since somebody's playlists can all be on the one
            // Google didn't pick.
            let channels = await withTimeLimit(seconds: 12) { () async -> [YouTube.AccountChannel]? in
                await YouTube.accountChannels()
            } ?? []

            await MainActor.run {
                guard !Task.isCancelled else {
                    Auth.shared.restore(snapshot)
                    return
                }
                let pending = PendingSignIn(cookie: cookie, visitorData: visitor, dataSyncId: dataSyncId,
                                            info: info, channels: channels)
                if channels.count > 1 {
                    channelChoice = pending
                } else {
                    complete(pending, channel: nil)
                }
            }
        }
    }

    private func complete(_ pending: PendingSignIn, channel: YouTube.AccountChannel?) {
        Auth.shared.finishSignIn(cookie: pending.cookie, visitorData: pending.visitorData,
                                 dataSyncId: pending.dataSyncId, info: pending.info, channel: channel)
        before = nil
        work = nil
        channelChoice = nil
        validating = false
        dismiss()
    }

    /// Stop finishing, and leave things as they were.
    private func cancelSignIn() {
        work?.cancel()
        work = nil
        if let before { Auth.shared.restore(before) }
        before = nil
        channelChoice = nil
        validating = false
    }

    // MARK: Channel chooser

    /// The channel in use: the one the page said, or else whichever the
    /// answer marks.
    private func activeChannel(_ choice: PendingSignIn) -> YouTube.AccountChannel? {
        if let named = choice.channels.first(where: { $0.id == choice.dataSyncId }) { return named }
        if let marked = choice.channels.first(where: { $0.isSelected }) { return marked }
        return choice.channels.first
    }

    private func channelChooser(_ choice: PendingSignIn) -> some View {
        let active = activeChannel(choice)
        return ZStack {
            // Closing it keeps the channel Google picked rather than leaving
            // the sign-in waiting on an answer that will never come.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { complete(choice, channel: active) }

            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a channel")
                    .font(.system(size: 18, weight: .bold))
                Text("Your playlists and library come from the channel you pick. You can change it later from your account.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 8)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(choice.channels) { channel in
                            Button { complete(choice, channel: channel) } label: {
                                channelRow(channel, selected: channel.id == active?.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(Blaze.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)
        }
    }

    private func channelRow(_ channel: YouTube.AccountChannel, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if let photo = channel.photo, let url = URL(string: photo) {
                    RemoteImage(url: url, size: 40, logo: false) { Circle().fill(Blaze.amber.opacity(0.3)) }
                } else {
                    Circle().fill(Blaze.amber.opacity(0.2))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(Blaze.amber))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let handle = channel.handle {
                    Text(handle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Blaze.amber)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(selected ? 0.08 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct LoginWebView: UIViewRepresentable {
    let freshStart: Bool
    let onLoading: (Bool) -> Void
    let onFailure: (String) -> Void
    /// (cookie, visitorData, dataSyncId)
    let onCapture: (String, String?, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A store of its own that lives only as long as this page, so Google
        // sees nobody signed in and asks which account to add.
        if freshStart { configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent() }
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        let url = URL(string: "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com")!
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: LoginWebView
        private var captured = false

        init(_ parent: LoginWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            failed(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failed(error)
        }

        /// A page Google replaced with the next one is not a failure, only noise.
        private func failed(_ error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            DispatchQueue.main.async { self.parent.onFailure(error.localizedDescription) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.onLoading(false) }
            guard !captured, webView.url?.host?.contains("music.youtube.com") == true else { return }

            webView.evaluateJavaScript("window.yt && yt.config_ ? yt.config_.VISITOR_DATA : null") { visitor, _ in
                webView.evaluateJavaScript("window.yt && yt.config_ ? yt.config_.DATASYNC_ID : null") { dataSync, _ in
                    let visitorData = visitor as? String
                    let dataSyncId = (dataSync as? String)?.components(separatedBy: "||").first
                    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        self.finish(cookies: cookies, visitorData: visitorData, dataSyncId: dataSyncId)
                    }
                }
            }
        }

        private func finish(cookies: [HTTPCookie], visitorData: String?, dataSyncId: String?) {
            let relevant = cookies.filter { $0.domain.contains("youtube.com") || $0.domain.contains("google.com") }
            let names = Set(relevant.map(\.name))
            // Not signed in yet — no SAPISID-family cookie.
            guard names.contains("SAPISID") || names.contains("__Secure-3PAPISID") else { return }

            // One cookie per name (prefer the youtube.com copy when a name is duplicated).
            var byName: [String: HTTPCookie] = [:]
            for cookie in relevant {
                if let existing = byName[cookie.name] {
                    if cookie.domain.contains("youtube.com"), !existing.domain.contains("youtube.com") {
                        byName[cookie.name] = cookie
                    }
                } else {
                    byName[cookie.name] = cookie
                }
            }
            let cookieString = byName.values.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

            captured = true
            DispatchQueue.main.async { self.parent.onCapture(cookieString, visitorData, dataSyncId) }
        }
    }
}
