import Foundation
import Testing
@testable import TraceCore

private func closed(_ n: UInt64) -> FlowEvent {
    .closed(FlowClosed(flowID: UUID(), time: Date(timeIntervalSince1970: 0), bytesIn: n, bytesOut: 0))
}

private func bytesIn(_ batch: EventBatch) -> [UInt64] {
    batch.events.map { event -> UInt64 in
        if case .closed(let c) = event { return c.bytesIn }
        return 0
    }
}

@Suite struct EventRingTests {
    @Test func drainsInFIFOOrder() {
        let ring = EventRing(capacity: 10)
        for i in 1...3 { ring.append(closed(UInt64(i))) }
        let batch = ring.drain(max: 10)
        #expect(bytesIn(batch) == [1, 2, 3])
        #expect(batch.droppedSinceLastBatch == 0)
        #expect(ring.count == 0)
    }
    @Test func partialDrainKeepsRest() {
        let ring = EventRing(capacity: 10)
        for i in 1...5 { ring.append(closed(UInt64(i))) }
        #expect(bytesIn(ring.drain(max: 2)) == [1, 2])
        #expect(bytesIn(ring.drain(max: 10)) == [3, 4, 5])
    }
    @Test func overflowDropsOldestAndCounts() {
        let ring = EventRing(capacity: 3)
        for i in 1...5 { ring.append(closed(UInt64(i))) }
        let batch = ring.drain(max: 10)
        #expect(bytesIn(batch) == [3, 4, 5])
        #expect(batch.droppedSinceLastBatch == 2)
        #expect(ring.drain(max: 10).droppedSinceLastBatch == 0)
    }
    @Test func wrapsAroundCorrectly() {
        let ring = EventRing(capacity: 3)
        for round in 0..<10 {
            ring.append(closed(UInt64(round * 2)))
            ring.append(closed(UInt64(round * 2 + 1)))
            #expect(bytesIn(ring.drain(max: 10)) == [UInt64(round * 2), UInt64(round * 2 + 1)])
        }
    }
}
