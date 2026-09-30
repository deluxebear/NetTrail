import Foundation
import Testing
@testable import TraceCore

@Suite struct DNSCacheTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func returnsInsertedHostUntilExpiry() {
        let cache = DNSCache(minTTL: 300)
        cache.insert(ip: "1.2.3.4", host: "a.com", ttl: 10, now: t0)
        #expect(cache.lookup(ip: "1.2.3.4", now: t0.addingTimeInterval(299)) == "a.com")
        #expect(cache.lookup(ip: "1.2.3.4", now: t0.addingTimeInterval(301)) == nil)
    }
    @Test func longTTLIsHonored() {
        let cache = DNSCache(minTTL: 300)
        cache.insert(ip: "1.2.3.4", host: "a.com", ttl: 3600, now: t0)
        #expect(cache.lookup(ip: "1.2.3.4", now: t0.addingTimeInterval(3500)) == "a.com")
    }
    @Test func lookupMatchesMappedIPv6() {
        let cache = DNSCache()
        cache.insert(ip: "1.2.3.4", host: "a.com", ttl: 60, now: t0)
        #expect(cache.lookup(ip: "::ffff:1.2.3.4", now: t0) == "a.com")
        cache.insert(ip: "2001:0db8::0001", host: "b.com", ttl: 60, now: t0)
        #expect(cache.lookup(ip: "2001:db8::1", now: t0) == "b.com")
    }
    @Test func newerAnswerReplacesOlder() {
        let cache = DNSCache()
        cache.insert(ip: "1.2.3.4", host: "a.com", ttl: 60, now: t0)
        cache.insert(ip: "1.2.3.4", host: "b.com", ttl: 60, now: t0.addingTimeInterval(1))
        #expect(cache.lookup(ip: "1.2.3.4", now: t0.addingTimeInterval(2)) == "b.com")
    }
    @Test func evictsEarliestExpiringWhenFull() {
        let cache = DNSCache(capacity: 100, minTTL: 1)
        for i in 0..<150 {
            cache.insert(ip: "10.0.\(i / 256).\(i % 256)", host: "h\(i).com", ttl: UInt32(1000 + i), now: t0)
        }
        #expect(cache.count <= 100)
        #expect(cache.lookup(ip: "10.0.0.149", now: t0) == "h149.com")
        #expect(cache.lookup(ip: "10.0.0.0", now: t0) == nil)
    }
    @Test func ignoresNonIPKeys() {
        let cache = DNSCache()
        cache.insert(ip: "not-an-ip", host: "a.com", ttl: 60, now: t0)
        #expect(cache.count == 0)
    }
}
