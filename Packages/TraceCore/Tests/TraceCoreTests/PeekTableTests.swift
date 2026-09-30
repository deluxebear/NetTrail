import Foundation
import Testing
@testable import TraceCore

private func pending(at time: Date) -> PendingOpen {
    PendingOpen(app: .unknown, remote: Endpoint(ip: "1.2.3.4", port: 443, proto: .tcp), startedAt: time)
}

@Suite struct PeekTableTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func appendAccumulatesUpToCap() {
        let table = PeekTable()
        let id = UUID()
        table.begin(id, pending(at: t0))
        _ = table.append(id, Data(repeating: 1, count: 3000))
        let result = table.append(id, Data(repeating: 2, count: 3000))
        #expect(result?.buffer.count == PayloadSniffer.maxPeekBytes)
    }
    @Test func takeReturnsOnlyOnce() {
        let table = PeekTable()
        let id = UUID()
        table.begin(id, pending(at: t0))
        #expect(table.take(id) != nil)
        #expect(table.take(id) == nil)
        #expect(table.append(id, Data([1])) == nil)
    }
    @Test func takeExpiredRemovesOnlyOldEntries() {
        let table = PeekTable()
        let old = UUID(), fresh = UUID()
        table.begin(old, pending(at: t0))
        table.begin(fresh, pending(at: t0.addingTimeInterval(5)))
        let expired = table.takeExpired(startedBefore: t0.addingTimeInterval(2))
        #expect(expired.map { $0.0 } == [old])
        #expect(table.count == 1)
        #expect(table.take(fresh) != nil)
    }
}
