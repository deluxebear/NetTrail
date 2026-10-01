import Foundation
import TraceCore

/// Owns the aggregator and performs every store write, keeping database work off the main actor.
public actor Ingestor {
    public struct Result: Sendable {
        public let droppedTotal: UInt64
        public let recent: [RecentApp]
        public let error: (any Error)?
    }

    private let store: Store
    private let aggregator: Aggregator

    public init(store: Store) {
        self.store = store
        let resolver = AppIdentityResolver()
        aggregator = Aggregator(store: store) { resolver.resolve($0) }
    }

    public func ingest(_ batch: EventBatch, paused: Bool, now: Date) -> Result {
        aggregator.isPaused = paused
        var failure: (any Error)?
        do {
            try aggregator.ingest(batch, now: now)
        } catch {
            failure = error
        }
        return Result(droppedTotal: aggregator.droppedTotal, recent: aggregator.recent.snapshot(now: now), error: failure)
    }

    public func recent(now: Date) -> [RecentApp] {
        aggregator.recent.snapshot(now: now)
    }

    public func purge(before date: Date) throws {
        try store.purge(before: date)
    }

    public func deleteAll() throws {
        try store.deleteAll()
    }
}
