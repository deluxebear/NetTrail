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
                ops.append(.open(app: app, domain: domain, resolved: flow.host != nil, source: flow.hostSource, time: flow.time,
                                 origin: originInfo(flow.origin, app: app)))
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

    private func originInfo(_ origin: ProcessOrigin?, app: ResolvedApp) -> OriginInfo? {
        guard let origin else { return nil }
        var via = ""
        var viaPath: String?
        if let path = origin.responsiblePath {
            let responsible = resolve(AppIdentity(signingID: nil, teamID: nil, bundleID: nil, executablePath: path, pid: 0))
            // A helper attributed to its own app (e.g. Slack Helper → Slack) adds nothing. Compare names too:
            // Chrome runs from a code-sign clone whose path does not resolve to the same key.
            if responsible.key != app.key, responsible.displayName != app.displayName {
                via = responsible.displayName
                viaPath = responsible.path
            }
        }
        return OriginInfo(via: via, viaPath: viaPath, script: origin.script ?? "",
                          chain: origin.ancestors.joined(separator: " ← "))
    }
}
