import Foundation

public struct PendingOpen: Sendable {
    public let app: AppIdentity
    public let remote: Endpoint
    public let startedAt: Date
    public var buffer: Data

    public init(app: AppIdentity, remote: Endpoint, startedAt: Date, buffer: Data = Data()) {
        self.app = app
        self.remote = remote
        self.startedAt = startedAt
        self.buffer = buffer
    }
}

/// Flows whose hostname is still being sniffed from outbound bytes. Thread-safe.
public final class PeekTable: @unchecked Sendable {
    private var table: [UUID: PendingOpen] = [:]
    private let lock = NSLock()

    public init() {}

    public var count: Int { lock.withLock { table.count } }

    public func begin(_ id: UUID, _ pending: PendingOpen) {
        lock.withLock { table[id] = pending }
    }

    /// Appends bytes (capped at `PayloadSniffer.maxPeekBytes`) and returns the updated state,
    /// or nil if the flow is no longer pending.
    public func append(_ id: UUID, _ data: Data) -> PendingOpen? {
        lock.withLock {
            guard var pending = table[id] else { return nil }
            let room = max(0, PayloadSniffer.maxPeekBytes - pending.buffer.count)
            pending.buffer.append(data.prefix(room))
            table[id] = pending
            return pending
        }
    }

    public func take(_ id: UUID) -> PendingOpen? {
        lock.withLock { table.removeValue(forKey: id) }
    }

    public func takeExpired(startedBefore cutoff: Date) -> [(UUID, PendingOpen)] {
        lock.withLock {
            let expired = table.filter { $0.value.startedAt < cutoff }
            for id in expired.keys { table[id] = nil }
            return expired.map { ($0.key, $0.value) }
        }
    }
}
