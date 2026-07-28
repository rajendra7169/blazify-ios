import Foundation
import Compression

/// Minimal protobuf wire-format reader/writer — enough for listentogether.proto,
/// without pulling in a code-generation dependency.
enum Proto {

    // MARK: Writing

    static func varint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    /// Length-delimited field (strings, bytes, embedded messages).
    static func field(_ number: Int, _ data: Data) -> Data {
        varint(UInt64(number << 3 | 2)) + varint(UInt64(data.count)) + data
    }

    static func field(_ number: Int, _ string: String) -> Data {
        field(number, Data(string.utf8))
    }

    /// Varint field (ints, bools). Zero is omitted, as proto3 requires.
    static func field(_ number: Int, int value: Int64) -> Data {
        guard value != 0 else { return Data() }
        return varint(UInt64(number << 3 | 0)) + varint(UInt64(bitPattern: value))
    }

    static func field(_ number: Int, bool value: Bool) -> Data {
        guard value else { return Data() }
        return varint(UInt64(number << 3 | 0)) + varint(1)
    }

    // MARK: Reading

    /// Field number → raw values. Length-delimited come back as Data,
    /// varints as UInt64.
    static func parse(_ data: Data) -> [Int: [Any]] {
        var out: [Int: [Any]] = [:]
        var i = data.startIndex

        func readVarint() -> UInt64? {
            var shift: UInt64 = 0
            var value: UInt64 = 0
            while i < data.endIndex {
                let byte = data[i]
                i = data.index(after: i)
                value |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }

        while i < data.endIndex {
            guard let key = readVarint() else { break }
            let number = Int(key >> 3)
            let wire = key & 7
            switch wire {
            case 0:
                guard let v = readVarint() else { return out }
                out[number, default: []].append(v)
            case 2:
                guard let len = readVarint() else { return out }
                let end = data.index(i, offsetBy: Int(len), limitedBy: data.endIndex) ?? data.endIndex
                out[number, default: []].append(Data(data[i..<end]))
                i = end
            case 5:
                i = data.index(i, offsetBy: 4, limitedBy: data.endIndex) ?? data.endIndex
            case 1:
                i = data.index(i, offsetBy: 8, limitedBy: data.endIndex) ?? data.endIndex
            default:
                return out
            }
        }
        return out
    }

    static func string(_ fields: [Int: [Any]], _ number: Int) -> String {
        guard let d = fields[number]?.first as? Data else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }

    static func int(_ fields: [Int: [Any]], _ number: Int) -> Int64 {
        guard let v = fields[number]?.first as? UInt64 else { return 0 }
        return Int64(bitPattern: v)
    }

    static func bool(_ fields: [Int: [Any]], _ number: Int) -> Bool {
        (fields[number]?.first as? UInt64).map { $0 != 0 } ?? false
    }

    static func message(_ fields: [Int: [Any]], _ number: Int) -> [Int: [Any]]? {
        guard let d = fields[number]?.first as? Data else { return nil }
        return parse(d)
    }

    static func messages(_ fields: [Int: [Any]], _ number: Int) -> [[Int: [Any]]] {
        (fields[number] as? [Data])?.map(parse) ?? []
    }

    /// The server gzips payloads over ~100 bytes; Foundation has no gunzip, so
    /// strip the gzip header and raw-inflate the deflate stream.
    static func gunzip(_ data: Data) -> Data? {
        guard data.count > 18, data[data.startIndex] == 0x1F,
              data[data.index(after: data.startIndex)] == 0x8B else { return nil }
        let flags = data[data.index(data.startIndex, offsetBy: 3)]
        var offset = 10
        if flags & 0x04 != 0 {   // FEXTRA
            let xlen = Int(data[data.index(data.startIndex, offsetBy: offset)]) |
                       Int(data[data.index(data.startIndex, offsetBy: offset + 1)]) << 8
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 {   // FNAME
            while offset < data.count, data[data.index(data.startIndex, offsetBy: offset)] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {   // FCOMMENT
            while offset < data.count, data[data.index(data.startIndex, offsetBy: offset)] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }   // FHCRC
        guard offset < data.count - 8 else { return nil }

        let body = Data(data[data.index(data.startIndex, offsetBy: offset)..<data.index(data.endIndex, offsetBy: -8)])
        let capacity = 1 << 20
        var out = Data()
        body.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return }
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { dst.deallocate() }
            let n = compression_decode_buffer(dst, capacity, base, body.count, nil, COMPRESSION_ZLIB)
            if n > 0 { out = Data(bytes: dst, count: n) }
        }
        return out.isEmpty ? nil : out
    }
}
