import SwiftUI
import WebKit

/// Google/YouTube-Music sign-in in a WKWebView — the same flow as Blazify Android.
/// On landing back on music.youtube.com with a valid session we capture the cookie
/// + visitorData + dataSyncId, validate via account_menu, and persist.
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var validating = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ZStack {
                LoginWebView { cookie, visitor, dataSyncId in
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
                .ignoresSafeArea(edges: .bottom)

                if validating {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    ProgressView("Signing in…")
                        .tint(Blaze.amber)
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
    /// (cookie, visitorData, dataSyncId)
    let onCapture: (String, String?, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

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
        private let onCapture: (String, String?, String?) -> Void
        private var captured = false

        init(onCapture: @escaping (String, String?, String?) -> Void) { self.onCapture = onCapture }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
            DispatchQueue.main.async { self.onCapture(cookieString, visitorData, dataSyncId) }
        }
    }
}
