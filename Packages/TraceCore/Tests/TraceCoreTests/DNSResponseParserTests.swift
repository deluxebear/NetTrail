import Foundation
import Testing
@testable import TraceCore

/// Real response for `www.apple.com A` (uncompressed CNAME chain + OPT record).
private let appleResponseHex = "12348180000100050000000103777777056170706c6503636f6d000001000103777777056170706c6503636f6d000005000100000028001d0d7777772d6170706c652d636f6d0176076161706c696d6703636f6d000d7777772d6170706c652d636f6d0176076161706c696d6703636f6d000005000100000028002303777777056170706c6503636f6d08646f776e6c6f6164066b732d63646e03636f6d0003777777056170706c6503636f6d08646f776e6c6f6164066b732d63646e03636f6d000005000100000028001e0a6b3132382d696e6170700467736c62086b7379756e63646e03636f6d000a6b3132382d696e6170700467736c62086b7379756e63646e03636f6d000005000100000028002d146b3132382d696e6170702d66636c6f7564646e730467736c62036e65770966636c6f7564646e73036e657400146b3132382d696e6170702d66636c6f7564646e730467736c62036e65770966636c6f7564646e73036e65740000010001000000280004b7f0894a00002904d0000000000000"

/// Real response for `example.com AAAA` with zero answers.
private let emptyResponseHex = "123485800001000000000000076578616d706c6503636f6d00001c0001"

private func label(_ s: String) -> [UInt8] { [UInt8(s.utf8.count)] + Array(s.utf8) }

/// www.example.com A with compression: CNAME -> edge.example.com, A, AAAA.
private func compressedResponse() -> Data {
    var m: [UInt8] = [0x12, 0x34, 0x81, 0x80] + be16(1) + be16(3) + be16(0) + be16(0)
    m += label("www") + label("example") + label("com") + [0] + be16(1) + be16(1)   // question at 12; "example" at 16
    m += [0xc0, 0x0c] + be16(5) + be16(1) + [0, 0, 0x01, 0x2c] + be16(7) + label("edge") + [0xc0, 0x10]
    m += [0xc0, 0x0c] + be16(1) + be16(1) + [0, 0, 0, 0x3c] + be16(4) + [93, 184, 216, 34]
    m += [0xc0, 0x0c] + be16(28) + be16(1) + [0, 0, 0, 0x78] + be16(16)
        + [0x26, 0x06, 0x28, 0x00] + Array(repeating: 0, count: 11) + [1]
    return Data(m)
}

@Suite struct DNSResponseParserTests {
    @Test func parsesRealCNAMEChainResponse() {
        let answer = DNSResponseParser.parse(Data(hex: appleResponseHex))
        #expect(answer == DNSAnswer(queryName: "www.apple.com",
                                    addresses: [.init(ip: "183.240.137.74", ttl: 40)]))
    }
    @Test func parsesCompressedNamesAndIPv6() {
        let answer = DNSResponseParser.parse(compressedResponse())
        #expect(answer?.queryName == "www.example.com")
        #expect(answer?.addresses == [.init(ip: "93.184.216.34", ttl: 60), .init(ip: "2606:2800::1", ttl: 120)])
    }
    @Test func responseWithoutAddressesIsNil() {
        #expect(DNSResponseParser.parse(Data(hex: emptyResponseHex)) == nil)
    }
    @Test func queryIsNil() {
        var m = [UInt8](compressedResponse())
        m[2] = 0x01   // clear QR bit
        #expect(DNSResponseParser.parse(Data(m)) == nil)
    }
    @Test func pointerLoopTerminates() {
        let m: [UInt8] = [0x12, 0x34, 0x81, 0x80] + be16(1) + be16(1) + be16(0) + be16(0) + [0xc0, 0x0c] + be16(1) + be16(1)
        #expect(DNSResponseParser.parse(Data(m)) == nil)
    }
    @Test func truncatedResponseIsNil() {
        #expect(DNSResponseParser.parse(Data(hex: appleResponseHex).prefix(100)) == nil)
        #expect(DNSResponseParser.parse(Data()) == nil)
    }
    @Test func survivesRandomAndMutatedInput() {
        let real = [UInt8](compressedResponse())
        for _ in 0..<2000 {
            _ = DNSResponseParser.parse(Data([0x12, 0x34, 0x81, 0x80] + randomBytes(count: Int.random(in: 0...400))))
            var mutated = real
            for _ in 0..<4 { mutated[Int.random(in: 0..<mutated.count)] = UInt8.random(in: 0...255) }
            _ = DNSResponseParser.parse(Data(mutated))
        }
    }
}
