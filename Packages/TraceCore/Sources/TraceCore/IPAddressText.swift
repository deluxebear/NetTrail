import Darwin

public enum IPAddressText {
    /// Canonical text for an IP literal, or nil if `raw` is not one.
    /// Strips brackets and zone IDs; IPv4-mapped IPv6 becomes dotted IPv4.
    public static func normalize(_ raw: String) -> String? {
        var text = raw
        if text.hasPrefix("["), text.hasSuffix("]") {
            text = String(text.dropFirst().dropLast())
        }
        if let zone = text.firstIndex(of: "%") {
            text = String(text[..<zone])
        }
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 {
            return fromBytes(withUnsafeBytes(of: &v4) { Array($0) })
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, text, &v6) == 1 {
            return fromBytes(withUnsafeBytes(of: &v6) { Array($0) })
        }
        return nil
    }

    /// Text for 4 or 16 network-order address bytes.
    public static func fromBytes(_ bytes: [UInt8]) -> String? {
        if bytes.count == 4 {
            return bytes.map { String($0) }.joined(separator: ".")
        }
        guard bytes.count == 16 else { return nil }
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
            return bytes[12...].map { String($0) }.joined(separator: ".")
        }
        var addr = in6_addr()
        withUnsafeMutableBytes(of: &addr) { $0.copyBytes(from: bytes) }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &addr, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
