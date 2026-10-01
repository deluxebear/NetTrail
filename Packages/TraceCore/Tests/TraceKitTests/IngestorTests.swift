import Foundation
import Testing
import TraceCore
@testable import TraceKit

private let curl = AppIdentity(signingID: "com.apple.curl", teamID: nil, bundleID: nil, executablePath: "/usr/bin/curl", pid: 9)

private func opened(_ host: String, at time: Date) -> FlowEvent {
    .opened(FlowOpened(flowID: UUID(), time: time, app: curl,
                       remote: Endpoint(ip: "1.2.3.4", port: 443, proto: .tcp),
                       host: host, hostSource: .sni))
}

@Suite struct IngestorTests {
    let t0 = hourAligned

    @Test func ingestWritesAndReportsState() async throws {
        let store = try Store.inMemory()
        let ingestor = Ingestor(store: store)
        let result = await ingestor.ingest(EventBatch(events: [opened("example.com", at: t0)], droppedSinceLastBatch: 3),
                                           paused: false, now: t0)
        #expect(result.error == nil)
        #expect(result.droppedTotal == 3)
        #expect(result.recent.map(\.domains) == [["example.com"]])
        #expect(try store.apps(range: .all, now: t0).count == 1)
    }

    @Test func pausedIngestWritesNothing() async throws {
        let store = try Store.inMemory()
        let ingestor = Ingestor(store: store)
        let result = await ingestor.ingest(EventBatch(events: [opened("example.com", at: t0)], droppedSinceLastBatch: 0),
                                           paused: true, now: t0)
        #expect(result.recent.isEmpty)
        #expect(try store.apps(range: .all, now: t0).isEmpty)
    }
}
