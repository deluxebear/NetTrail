import Foundation
import Testing
@testable import TraceCore

@Suite struct FlowCountersTests {
    @Test func reportsIncrementsUntilFinished() {
        let counters = FlowCounters()
        let id = UUID()
        #expect(counters.advance(id, totalIn: 100, totalOut: 10) == .init(bytesIn: 100, bytesOut: 10))
        #expect(counters.advance(id, totalIn: 100, totalOut: 10).isZero)
        #expect(counters.advance(id, totalIn: 250, totalOut: 12) == .init(bytesIn: 150, bytesOut: 2))
        #expect(counters.finish(id, totalIn: 300, totalOut: 12) == .init(bytesIn: 50, bytesOut: 0))
        #expect(counters.count == 0)
    }

    @Test func closeWithoutStatisticsReportsEverything() {
        let counters = FlowCounters()
        #expect(counters.finish(UUID(), totalIn: 7, totalOut: 3) == .init(bytesIn: 7, bytesOut: 3))
    }

    @Test func shrinkingTotalsNeverGoNegative() {
        let counters = FlowCounters()
        let id = UUID()
        _ = counters.advance(id, totalIn: 100, totalOut: 100)
        #expect(counters.advance(id, totalIn: 40, totalOut: 120) == .init(bytesIn: 0, bytesOut: 20))
        #expect(counters.advance(id, totalIn: 110, totalOut: 120) == .init(bytesIn: 10, bytesOut: 0))
    }
}
