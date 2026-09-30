import Foundation
import Testing
@testable import TraceCore

@Suite struct SNIParserTests {
    @Test func parsesRealCurlClientHello() {
        #expect(SNIParser.parse(Data(hex: curlClientHelloHex)) == .found("www.example.com"))
    }
    @Test func findsSNIAfterGreaseAndLargeExtensions() {
        let data = clientHello(extensions: [
            (0x0a0a, []),
            (0x0033, Array(repeating: 0x42, count: 1200)),
            sniExtension("api.slack.com"),
        ])
        #expect(SNIParser.parse(data) == .found("api.slack.com"))
    }
    @Test func normalizesCaseAndTrailingDot() {
        let data = clientHello(extensions: [sniExtension("API.Example.COM.")])
        #expect(SNIParser.parse(data) == .found("api.example.com"))
    }
    @Test func rejectsIPLiteralSNI() {
        let data = clientHello(extensions: [sniExtension("1.2.3.4")])
        #expect(SNIParser.parse(data) == .notFound)
    }
    @Test func completeHelloWithoutSNIIsNotFound() {
        let data = clientHello(extensions: [(0x000b, [0x01, 0x00])])
        #expect(SNIParser.parse(data) == .notFound)
    }
    @Test func truncatedHelloNeedsMore() {
        let full = Data(hex: curlClientHelloHex)
        #expect(SNIParser.parse(full.prefix(200)) == .needMore)
        #expect(SNIParser.parse(full.prefix(3)) == .needMore)
        #expect(SNIParser.parse(Data()) == .needMore)
    }
    @Test func nonTLSIsNotFound() {
        #expect(SNIParser.parse(Data("GET / HTTP/1.1\r\n".utf8)) == .notFound)
        #expect(SNIParser.parse(Data([0x16, 0x07, 0x00, 0x00, 0x10])) == .notFound)
    }
    @Test func survivesRandomAndMutatedInput() {
        let real = [UInt8](Data(hex: curlClientHelloHex))
        for _ in 0..<2000 {
            _ = SNIParser.parse(Data([0x16, 0x03] + randomBytes(count: Int.random(in: 0...600))))
            var mutated = real
            for _ in 0..<4 { mutated[Int.random(in: 0..<mutated.count)] = UInt8.random(in: 0...255) }
            _ = SNIParser.parse(Data(mutated))
        }
    }
}
