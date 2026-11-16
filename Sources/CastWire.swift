import Foundation

/// One message to or from a Google Cast device (a Chromecast, a TV with one built in, a Nest
/// speaker or display): from whom, to whom, in which channel, and its JSON text.
struct CastMessage: Equatable {
    var source: String
    var destination: String
    var namespace: String
    var payload: String
}

/// How cast devices frame their messages: each is a small protocol-buffer record, written by hand
/// here as it has only a few fields, after four bytes giving its length.
enum CastWire {
    static func encode(_ message: CastMessage) -> Data {
        var body = Data()
        varintField(1, 0, into: &body) // protocol version 1.0
        textField(2, message.source, into: &body)
        textField(3, message.destination, into: &body)
        textField(4, message.namespace, into: &body)
        varintField(5, 0, into: &body) // the payload is text
        textField(6, message.payload, into: &body)
        let size = UInt32(body.count)
        var framed = Data([UInt8(size >> 24 & 0xff), UInt8(size >> 16 & 0xff), UInt8(size >> 8 & 0xff), UInt8(size & 0xff)])
        framed.append(body)
        return framed
    }

    /// Reads one record, without its length; nil when it isn't one or carries no text.
    static func decode(_ body: [UInt8]) -> CastMessage? {
        var source: String?
        var destination: String?
        var namespace: String?
        var payload: String?
        var at = 0
        func varint() -> UInt64? {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while at < body.count, shift < 64 {
                let byte = body[at]
                at += 1
                value |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
            return nil
        }
        while at < body.count {
            guard let key = varint() else { return nil }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard varint() != nil else { return nil }
            case 1:
                at += 8
            case 2:
                guard let length = varint(), length <= UInt64(body.count - at) else { return nil }
                let text = String(decoding: body[at ..< at + Int(length)], as: UTF8.self)
                at += Int(length)
                switch field {
                case 2: source = text
                case 3: destination = text
                case 4: namespace = text
                case 6: payload = text
                default: break
                }
            case 5:
                at += 4
            default:
                return nil
            }
        }
        guard let source, let destination, let namespace, let payload else { return nil }
        return CastMessage(source: source, destination: destination, namespace: namespace, payload: payload)
    }

    private static func varint(_ value: UInt64, into out: inout Data) {
        var rest = value
        while true {
            if rest & ~0x7f == 0 {
                out.append(UInt8(rest))
                return
            }
            out.append(UInt8(rest & 0x7f) | 0x80)
            rest >>= 7
        }
    }

    private static func varintField(_ field: Int, _ value: UInt64, into out: inout Data) {
        varint(UInt64(field << 3), into: &out)
        varint(value, into: &out)
    }

    private static func textField(_ field: Int, _ text: String, into out: inout Data) {
        let bytes = Array(text.utf8)
        varint(UInt64(field << 3 | 2), into: &out)
        varint(UInt64(bytes.count), into: &out)
        out.append(contentsOf: bytes)
    }
}

/// Gathers the bytes a cast device sends, which come in pieces of any size, into whole messages.
struct CastFramer {
    private var pending: [UInt8] = []
    /// Cast devices never send a message near this size.
    private static let maxMessage = 1 << 20

    mutating func feed(_ bytes: Data) -> [CastMessage] {
        pending.append(contentsOf: bytes)
        var messages: [CastMessage] = []
        while pending.count >= 4 {
            let size = Int(pending[0]) << 24 | Int(pending[1]) << 16 | Int(pending[2]) << 8 | Int(pending[3])
            if size > Self.maxMessage {
                // Not a cast device, or lost in its stream: nothing more can be read from it.
                pending.removeAll()
                break
            }
            if pending.count < 4 + size { break }
            if let message = CastWire.decode(Array(pending[4 ..< 4 + size])) { messages.append(message) }
            pending.removeFirst(4 + size)
        }
        return messages
    }
}
