import Foundation
import UIKit

/// Reporting a problem without leaving the app.
///
/// There is nothing clever here, and that is the point. Most reports that
/// never arrive are lost at the step where somebody has to find out where to
/// send one, then work out which version they are running, then describe their
/// phone. This fills that in and leaves them the part only they can write.
///
/// The details are shown before anything is sent. An app that quietly gathers
/// facts about someone's device and posts them is the sort of thing this one
/// exists not to be, even when the facts are dull.
enum BugReport {
    private static let owner = "rajendra7169"
    private static let repo = "blazify-ios"
    private static let email = "rajendrapandey199971@gmail.com"

    /// Everything that would otherwise be the first three questions of a reply.
    static func details() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        return """
        Blazify \(version) (\(build), iOS)
        \(device.systemName) \(device.systemVersion)
        \(hardware())
        Language \(Locale.current.identifier)
        """
    }

    /// `UIDevice.model` says "iPhone" for every iPhone ever made, which is no
    /// use in a bug report. The machine identifier says which one.
    private static func hardware() -> String {
        var info = utsname()
        uname(&info)
        let identifier = withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: info.machine)) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
        return identifier
    }

    private static func body() -> String {
        """
        What happened:


        What you expected instead:


        How to make it happen again:
        1.
        2.

        ---
        \(details())
        """
    }

    /// The tracker needs an account, and most people who play music do not have
    /// one. This asks for nothing but the mail app they already have.
    static func openEmail() {
        let subject = encode("Blazify \(shortVersion()): ")
        open("mailto:\(email)?subject=\(subject)&body=\(encode(body()))")
    }

    static func openTracker() {
        open("https://github.com/\(owner)/\(repo)/issues/new?body=\(encode(body()))")
    }

    /// For anyone with neither a mail account nor a GitHub one.
    static func copyDetails() {
        UIPasteboard.general.string = body()
    }

    private static func shortVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }

    /// A literal plus is a space to a mail client, so encode it out.
    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
}
