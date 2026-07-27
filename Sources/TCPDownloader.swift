import Foundation
import Network

/// Minimal HTTPS GET over an explicit TCP connection (HTTP/1.1, never QUIC).
///
/// iOS URLSession — and AVPlayer's mediaplaybackd — reach googlevideo over QUIC
/// (HTTP/3), which returns 403 for YouTube's signed stream URLs; the exact same
/// URLs serve 200 over TCP. There is no public URLSession switch to disable HTTP/3
/// once the system has cached the route, so we run the fetch ourselves over a
/// TCP+TLS connection with ALPN pinned to "http/1.1".
enum TCPDownloader {

    /// Fetch `url` over TCP. `completion` fires on a background queue with the body
    /// bytes and the HTTP status code (nil/​nil on transport failure).
    static func get(_ url: URL, userAgent: String, completion: @escaping (Data?, Int?) -> Void) {
        guard let host = url.host else { completion(nil, nil); return }
        let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 443)) ?? .https
        let queue = DispatchQueue(label: "blazify.tcp-download")

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: params)

        var buffer = Data()
        var done = false
        var headerParsed = false
        var bodyStart = 0
        var contentLength: Int?
        var isChunked = false
        var status: Int?

        func finish(_ data: Data?, _ code: Int?) {
            if done { return }
            done = true
            conn.cancel()
            completion(data, code)
        }

        func emitBody() {
            var body = buffer.subdata(in: bodyStart..<buffer.count)
            if isChunked { body = dechunk(body) }
            finish(body, status)
        }

        func parseHeadersIfNeeded() {
            guard !headerParsed, let sep = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }
            headerParsed = true
            bodyStart = sep.upperBound
            let head = String(data: buffer.subdata(in: 0..<sep.lowerBound), encoding: .utf8) ?? ""
            let lines = head.components(separatedBy: "\r\n")
            let statusParts = (lines.first ?? "").split(separator: " ")
            status = statusParts.count >= 2 ? Int(statusParts[1]) : nil
            for line in lines.dropFirst() {
                let kv = line.split(separator: ":", maxSplits: 1)
                guard kv.count == 2 else { continue }
                let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
                let val = kv[1].trimmingCharacters(in: .whitespaces)
                if key == "content-length" { contentLength = Int(val) }
                if key == "transfer-encoding", val.lowercased().contains("chunked") { isChunked = true }
            }
        }

        func receiveLoop() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { data, _, isComplete, error in
                if let data, !data.isEmpty { buffer.append(data) }
                parseHeadersIfNeeded()
                if headerParsed, !isChunked, let cl = contentLength, buffer.count - bodyStart >= cl {
                    emitBody(); return
                }
                if error != nil { headerParsed ? emitBody() : finish(nil, nil); return }
                if isComplete { headerParsed ? emitBody() : finish(nil, nil); return }
                receiveLoop()
            }
        }

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let prefix = "\(url.scheme ?? "https")://\(host)"
                let target = url.absoluteString.hasPrefix(prefix)
                    ? String(url.absoluteString.dropFirst(prefix.count))
                    : url.path + (url.query.map { "?\($0)" } ?? "")
                var req = "GET \(target.isEmpty ? "/" : target) HTTP/1.1\r\n"
                req += "Host: \(host)\r\n"
                req += "User-Agent: \(userAgent)\r\n"
                req += "Accept: */*\r\n"
                req += "Connection: close\r\n\r\n"
                conn.send(content: Data(req.utf8), completion: .contentProcessed { err in
                    if err != nil { finish(nil, nil) }
                })
                receiveLoop()
            case .failed, .cancelled:
                finish(nil, nil)
            default:
                break
            }
        }

        // Watchdog so a stalled connection can't hang the loader forever. Runs on the
        // same serial queue as the connection callbacks, so `finish` never races.
        queue.asyncAfter(deadline: .now() + 30) { finish(nil, nil) }
        conn.start(queue: queue)
    }

    /// Decode HTTP chunked transfer-encoding (defensive; googlevideo usually sends
    /// Content-Length with Connection: close, but handle chunked just in case).
    private static func dechunk(_ data: Data) -> Data {
        var out = Data()
        var i = 0
        while i < data.count {
            guard let crlf = data.range(of: Data("\r\n".utf8), in: i..<data.count) else { break }
            let sizeStr = String(data: data.subdata(in: i..<crlf.lowerBound), encoding: .utf8) ?? ""
            let size = Int(sizeStr.split(separator: ";").first.map(String.init) ?? "", radix: 16) ?? 0
            if size == 0 { break }
            let start = crlf.upperBound
            let end = min(start + size, data.count)
            out.append(data.subdata(in: start..<end))
            i = end + 2   // skip the chunk's trailing CRLF
        }
        return out
    }
}
