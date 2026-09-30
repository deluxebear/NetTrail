import Foundation
import Testing
import TraceCore
@testable import TraceKit

private let curl = AppIdentity(signingID: "com.apple.curl", teamID: nil, bundleID: nil, executablePath: "/usr/bin/curl", pid: 9)

private func opened(_ id: UUID, host: String?, at time: Date) -> FlowEvent {
    .opened(FlowOpened(flowID: id, time: time, app: curl,
                       remote: Endpoint(ip: "1.2.3.4", port: 443, proto: .tcp),
                       host: host, hostSource: host == nil ? .none : .sni))
}

private func closed(_ id: UUID, at time: Date, bytesIn: UInt64 = 100, bytesOut: UInt64 = 10) -> FlowEvent {
    .closed(FlowClosed(flowID: id, time: time, bytesIn: bytesIn, bytesOut: bytesOut))
}

private func makeAggregator(_ store: Store, pendingTTL: TimeInterval = 86_400) -> Aggregator {
    Aggregator(store: store, pendingTTL: pendingTTL) {
        ResolvedApp(key: $0.signingID ?? $0.executablePath, displayName: "curl", bundleID: nil,
                    path: $0.executablePath, teamID: nil)
    }
}

@Suite struct AggregatorTests {
    let t0 = hourAligned

    @Test func openAndCloseAcrossBatches() throws {
        let store = try Store.inMemory()
        let aggregator = makeAggregator(store)
        let id = UUID()
        try aggregator.ingest(EventBatch(events: [opened(id, host: "example.com", at: t0)], droppedSinceLastBatch: 0), now: t0)
        #expect(aggregator.pendingCount == 1)
        try aggregator.ingest(EventBatch(events: [closed(id, at: t0.addingTimeInterval(5))], droppedSinceLastBatch: 0), now: t0)
        #expect(aggregator.pendingCount == 0)
        let summary = try #require(try store.apps(range: .all, now: t0).first)
        #expect(summary.key == "com.apple.curl" && summary.connCount == 1 && summary.bytesIn == 100 && summary.bytesOut == 10)
    }

    @Test func closeWithoutOpenIsIgnored() throws {
        let store = try Store.inMemory()
        let aggregator = makeAggregator(store)
        try aggregator.ingest(EventBatch(events: [closed(UUID(), at: t0)], droppedSinceLastBatch: 0), now: t0)
        #expect(try store.apps(range: .all, now: t0).isEmpty)
    }

    @Test func unresolvedHostFallsBackToIP() throws {
        let store = try Store.inMemory()
        let aggregator = makeAggregator(store)
        try aggregator.ingest(EventBatch(events: [opened(UUID(), host: nil, at: t0)], droppedSinceLastBatch: 0), now: t0)
        let domain = try #require(try store.domains(appID: nil, range: .all, now: t0).first)
        #expect(domain.domain == "1.2.3.4" && !domain.resolved && domain.lastSource == .none)
    }

    @Test func pausedIngestWritesNothing() throws {
        let store = try Store.inMemory()
        let aggregator = makeAggregator(store)
        aggregator.isPaused = true
        try aggregator.ingest(EventBatch(events: [opened(UUID(), host: "example.com", at: t0)], droppedSinceLastBatch: 2), now: t0)
        #expect(try store.apps(range: .all, now: t0).isEmpty)
        #expect(aggregator.recent.snapshot(now: t0).isEmpty)
        #expect(aggregator.droppedTotal == 2)
    }

    @Test func droppedCountsAccumulate() throws {
        let aggregator = makeAggregator(try Store.inMemory())
        try aggregator.ingest(EventBatch(events: [], droppedSinceLastBatch: 3), now: t0)
        try aggregator.ingest(EventBatch(events: [], droppedSinceLastBatch: 4), now: t0)
        #expect(aggregator.droppedTotal == 7)
    }

    @Test func stalePendingFlowsExpire() throws {
        let store = try Store.inMemory()
        let aggregator = makeAggregator(store, pendingTTL: 60)
        let id = UUID()
        try aggregator.ingest(EventBatch(events: [opened(id, host: "example.com", at: t0)], droppedSinceLastBatch: 0), now: t0)
        try aggregator.ingest(EventBatch(events: [], droppedSinceLastBatch: 0), now: t0.addingTimeInterval(61))
        #expect(aggregator.pendingCount == 0)
        try aggregator.ingest(EventBatch(events: [closed(id, at: t0.addingTimeInterval(62))], droppedSinceLastBatch: 0), now: t0.addingTimeInterval(62))
        #expect(try store.apps(range: .all, now: t0).first?.bytesIn == 0)
    }

    @Test func feedsRecentActivity() throws {
        let aggregator = makeAggregator(try Store.inMemory())
        try aggregator.ingest(EventBatch(events: [opened(UUID(), host: "example.com", at: t0)], droppedSinceLastBatch: 0), now: t0)
        #expect(aggregator.recent.snapshot(now: t0).first?.domains == ["example.com"])
    }
}
