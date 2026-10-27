import SwiftUI
import WebKit

/// Google / YouTube Music sign-in in a WKWebView.
/// On landing back on music.youtube.com with a valid session we capture the cookie
/// + visitorData + dataSyncId, validate via account_menu, and persist.
struct LoginView: View {
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

    var body: some View {
        NavigationStack {
            ZStack {
                LoginWebView(onLoading: { pageLoading = $0 },
                             onFailure: { loadError = $0 }) { cookie, visitor, dataSyncId in
                    guard !validating else { return }
                    validating = true
                    Task {
                        let ok = await Auth.shared.signIn(cookie: cookie, visitorData: visitor, dataSyncId: dataSyncId)
                        await MainActor.run {
                            validating = false
                            if ok { dismiss() } else { failed = true }
                        }
                    }
                }
                .id(attempt)
                .ignoresSafeArea(edges: .bottom)

                if let loadError {
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

                if validating {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 10) {
                        BlazeLoader(size: 64, tint: Blaze.amber)
                        Text("Signing in…")
                    }
                        .foregroundStyle(.white)
                        .padding(24)
                        .background(Blaze.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Blaze.amber)
                }
            }
            .alert("Sign-in failed", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Couldn't verify that account. Please try again.")
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct LoginWebView: UIViewRepresentable {
    let onLoading: (Bool) -> Void
    let onFailure: (String) -> Void
    /// (cookie, visitorData, dataSyncId)
    let onCapture: (String, String?, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
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
