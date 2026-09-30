import Foundation

public struct DNSAnswer: Equatable, Sendable {
    public struct Address: Equatable, Sendable {
        public let ip: String
        public let ttl: UInt32
        public init(ip: String, ttl: UInt32) {
            self.ip = ip
            self.ttl = ttl
        }
    }

    public let queryName: String
    public let addresses: [Address]

    public init(queryName: String, addresses: [Address]) {
        self.queryName = queryName
        self.addresses = addresses
    }
}

public enum DNSResponseParser {
    private static let typeA: UInt16 = 1
    private static let typeAAAA: UInt16 = 28
    private static let maxPointerJumps = 16

    public static func parse(_ data: Data) -> DNSAnswer? {
        let message = [UInt8](data)
        var r = ByteReader(message)
        guard r.u16() != nil, let flags = r.u16(), let questionCount = r.u16(),
              let answerCount = r.u16(), r.skip(4) else { return nil }
        guard flags & 0x8000 != 0, questionCount >= 1 else { return nil }
        guard let queryName = readName(message, &r), r.skip(4) else { return nil }
        for _ in 1..<Int(questionCount) {
            guard readName(message, &r) != nil, r.skip(4) else { return nil }
        }
        var addresses: [DNSAnswer.Address] = []
        for _ in 0..<Int(answerCount) {
            guard readName(message, &r) != nil, let type = r.u16(), r.skip(2),
                  let ttl = r.u32(), let length = r.u16(),
                  let rdata = r.take(Int(length)) else { break }
            let isAddress = (type == typeA && length == 4) || (type == typeAAAA && length == 16)
            if isAddress, let ip = IPAddressText.fromBytes(Array(rdata)) {
                addresses.append(.init(ip: ip, ttl: ttl))
            }
        }
        guard let name = HostNormalizer.normalizeDomain(queryName), !addresses.isEmpty else { return nil }
        return DNSAnswer(queryName: name, addresses: addresses)
    }

    /// Reads a possibly-compressed name at `r.offset`, advancing `r` past it.
    static func readName(_ message: [UInt8], _ r: inout ByteReader) -> String? {
        var labels: [String] = []
        var position = r.offset
        var jumped = false
        var jumps = 0
        var totalLength = 0
        while true {
            guard position < message.count else { return nil }
            let length = Int(message[position])
            if length == 0 {
                if !jumped { r.offset = position + 1 }
                break
            }
            if length & 0xC0 == 0xC0 {
                guard position + 1 < message.count else { return nil }
                let pointer = (length & 0x3F) << 8 | Int(message[position + 1])
                if !jumped { r.offset = position + 2 }
                jumped = true
                jumps += 1
                guard jumps <= maxPointerJumps, pointer < message.count else { return nil }
                position = pointer
                continue
            }
            guard length & 0xC0 == 0, position + 1 + length <= message.count else { return nil }
            labels.append(String(decoding: message[(position + 1)..<(position + 1 + length)], as: UTF8.self))
            totalLength += length + 1
            guard totalLength <= 255 else { return nil }
            position += 1 + length
        }
        return labels.joined(separator: ".")
    }
}
