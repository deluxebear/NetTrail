import Foundation
import TraceCore

/// Turns extension events into store writes. Not thread-safe; use from one actor.
public final class Aggregator {
    private struct PendingFlow {
        let appKey: String
        let domain: String
        let openedAt: Date
    }

    private let store: Store
    private let resolve: (AppIdentity) -> ResolvedApp
    private let pendingTTL: TimeInterval
    private var pending: [UUID: PendingFlow] = [:]

    public let recent: RecentActivity
    public var isPaused = false
    public private(set) var droppedTotal: UInt64 = 0
    public var pendingCount: Int { pending.count }

    public init(store: Store, recent: RecentActivity = RecentActivity(), pendingTTL: TimeInterval = 86_400,
                resolve: @escaping (AppIdentity) -> ResolvedApp) {
        self.store = store
        self.recent = recent
        self.pendingTTL = pendingTTL
        self.resolve = resolve
    }

    public func ingest(_ batch: EventBatch, now: Date) throws {
        droppedTotal += batch.droppedSinceLastBatch
        let cutoff = now.addingTimeInterval(-pendingTTL)
        pending = pending.filter { $0.value.openedAt >= cutoff }
        guard !isPaused else { return }

        var ops: [StoreOp] = []
        for event in batch.events {
            switch event {
            case .opened(let flow):
                let app = resolve(flow.app)
                let domain = flow.host ?? flow.remote.ip
                ops.append(.open(app: app, domain: domain, resolved: flow.host != nil, source: flow.hostSource, time: flow.time))
                pending[flow.flowID] = PendingFlow(appKey: app.key, domain: domain, openedAt: flow.time)
                recent.record(app: app, domain: domain, time: flow.time)
            case .closed(let flow):
                guard let open = pending.removeValue(forKey: flow.flowID) else { continue }
                ops.append(.close(appKey: open.appKey, domain: open.domain, time: flow.time,
                                  bytesIn: flow.bytesIn, bytesOut: flow.bytesOut))
            }
        }
        try store.apply(ops)
    }
}
