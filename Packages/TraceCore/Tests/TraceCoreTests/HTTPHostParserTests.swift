import Foundation
import Testing
@testable import TraceCore

private func http(_ text: String) -> Data { Data(text.utf8) }

@Suite struct HTTPHostParserTests {
    @Test func parsesHostAndStripsPort() {
        let data = http("GET /x HTTP/1.1\r\nHost: Example.com:8080\r\nAccept: */*\r\n\r\n")
        #expect(HTTPHostParser.parse(data) == .found("example.com"))
    }
    @Test func acceptsTerminatedHostLineBeforeHeadersEnd() {
        #expect(HTTPHostParser.parse(http("POST / HTTP/1.1\r\nhost: api.test.io\r\nContent-")) == .found("api.test.io"))
    }
    @Test func truncatedHostLineNeedsMore() {
        #expect(HTTPHostParser.parse(http("GET / HTTP/1.1\r\nHost: exam")) == .needMore)
    }
    @Test func partialMethodNeedsMore() {
        #expect(HTTPHostParser.parse(http("GE")) == .needMore)
    }
    @Test func completeHeadersWithoutHostIsNotFound() {
        #expect(HTTPHostParser.parse(http("GET / HTTP/1.0\r\nAccept: */*\r\n\r\n")) == .notFound)
    }
    @Test func nonHTTPIsNotFound() {
        #expect(HTTPHostParser.parse(Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])) == .notFound)
        #expect(HTTPHostParser.parse(http("SSH-2.0-OpenSSH_9.0\r\n")) == .notFound)
    }
    @Test func ipv6LiteralHostIsNotFound() {
        #expect(HTTPHostParser.parse(http("GET / HTTP/1.1\r\nHost: [::1]:80\r\n\r\n")) == .notFound)
    }
}

@Suite struct PayloadSnifferTests {
    @Test func tlsUsesSNI() {
        #expect(PayloadSniffer.sniff(Data(hex: curlClientHelloHex)) == .found(host: "www.example.com", source: .sni))
    }
    @Test func httpUsesHostHeader() {
        #expect(PayloadSniffer.sniff(http("GET / HTTP/1.1\r\nHost: a.b.c\r\n\r\n")) == .found(host: "a.b.c", source: .httpHost))
    }
    @Test func emptyNeedsMore() {
        #expect(PayloadSniffer.sniff(Data()) == .needMore)
    }
    @Test func otherProtocolsAreNotFound() {
        #expect(PayloadSniffer.sniff(http("SSH-2.0-OpenSSH_9.0\r\n")) == .notFound)
    }
}
