import Foundation

/// Blazify Project (C) 2026
/// Licensed under GPL-3.0

/// What the picture behind the player did, step by step, for reading after.
///
/// "It doesn't play" is the hardest report to act on, and this is the one
/// place in the app where it cannot be acted on from a desk: the stream plays
/// here and not there, and there is no Mac to attach to the phone. So each
/// step says what it did — the gate, the lookup, the player's state changes,
/// any error with its domain and code — into a short memory that Settings ›
/// Report a problem can copy out. Nothing here leaves the phone on its own.
enum VideoArtLog {
    private static var lines: [String] = []
    private static let keep = 300
    private static let lock = NSLock()
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func note(_ message: String) {
        let line = "\(clock.string(from: Date())) \(message)"
        lock.lock()
        lines.append(line)
        if lines.count > keep { lines.removeFirst(lines.count - keep) }
        lock.unlock()
        #if DEBUG
        print("[VideoArt] \(message)")
        #endif
    }

    /// "file" or "hls" — the address itself is a signed one and is not
    /// written down. Here rather than on the loader, which is bound to the
    /// main actor, because the player's builder and the screen's coordinator
    /// are not, and a call across that line does not compile.
    static func kind(of url: URL) -> String {
        url.absoluteString.contains("/hls_") || url.absoluteString.contains("manifest") ? "hls" : "file"
    }

    static var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.isEmpty ? "Nothing recorded yet." : lines.joined(separator: "\n")
    }
}
