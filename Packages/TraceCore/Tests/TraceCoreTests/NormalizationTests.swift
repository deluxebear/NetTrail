import Testing
@testable import TraceCore

@Suite struct IPAddressTextTests {
    @Test func normalizesIPv4() {
        #expect(IPAddressText.normalize("8.8.8.8") == "8.8.8.8")
    }
    @Test func canonicalizesIPv6() {
        #expect(IPAddressText.normalize("2001:0DB8:0000::0001") == "2001:db8::1")
    }
    @Test func unwrapsIPv4MappedIPv6() {
        #expect(IPAddressText.normalize("::ffff:1.2.3.4") == "1.2.3.4")
    }
    @Test func stripsZoneAndBrackets() {
        #expect(IPAddressText.normalize("[fe80::1%en0]") == "fe80::1")
    }
    @Test func rejectsHostnames() {
        #expect(IPAddressText.normalize("example.com") == nil)
        #expect(IPAddressText.normalize("") == nil)
    }
    @Test func formatsRawBytes() {
        #expect(IPAddressText.fromBytes([192, 168, 1, 1]) == "192.168.1.1")
        let v6: [UInt8] = [0x20, 0x01, 0x0d, 0xb8] + Array(repeating: 0, count: 11) + [1]
        #expect(IPAddressText.fromBytes(v6) == "2001:db8::1")
        let mapped: [UInt8] = Array(repeating: 0, count: 10) + [0xff, 0xff, 10, 0, 0, 1]
        #expect(IPAddressText.fromBytes(mapped) == "10.0.0.1")
        #expect(IPAddressText.fromBytes([1, 2, 3]) == nil)
    }
}

@Suite struct HostNormalizerTests {
    @Test func lowercasesAndTrimsTrailingDot() {
        #expect(HostNormalizer.normalizeDomain("WWW.Example.COM.") == "www.example.com")
        #expect(HostNormalizer.normalizeDomain("  api.test.io \n") == "api.test.io")
    }
    @Test func rejectsIPLiterals() {
        #expect(HostNormalizer.normalizeDomain("1.2.3.4") == nil)
        #expect(HostNormalizer.normalizeDomain("::1") == nil)
    }
    @Test func rejectsInvalidInput() {
        #expect(HostNormalizer.normalizeDomain(nil) == nil)
        #expect(HostNormalizer.normalizeDomain("") == nil)
        #expect(HostNormalizer.normalizeDomain("exa mple.com") == nil)
        #expect(HostNormalizer.normalizeDomain("ex\u{0}ample.com") == nil)
        #expect(HostNormalizer.normalizeDomain("bücher.de") == nil)
        #expect(HostNormalizer.normalizeDomain("a..b") == nil)
        #expect(HostNormalizer.normalizeDomain(".example.com") == nil)
    }
    @Test func acceptsPunycodeAndUnderscore() {
        #expect(HostNormalizer.normalizeDomain("xn--bcher-kva.de") == "xn--bcher-kva.de")
        #expect(HostNormalizer.normalizeDomain("_dmarc.example.com") == "_dmarc.example.com")
    }
    @Test func rejectsOverlongNames() {
        #expect(HostNormalizer.normalizeDomain(String(repeating: "a", count: 254)) == nil)
    }
}
