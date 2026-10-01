import Foundation

/// Turns the cumulative byte counts of filter reports into increments, so traffic is
/// counted while a flow is still open. Thread-safe.
public final class FlowCounters: @unchecked Sendable {
    public struct Bytes: Equatable, Sendable {
        public let bytesIn: UInt64
        public let bytesOut: UInt64
        public var isZero: Bool { bytesIn == 0 && bytesOut == 0 }
    }

    private var reported: [UUID: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private let lock = NSLock()

    public init() {}

    public var count: Int { lock.withLock { reported.count } }

    /// Bytes beyond what was last reported for `id`; totals never move backwards.
    public func advance(_ id: UUID, totalIn: UInt64, totalOut: UInt64) -> Bytes {
        lock.withLock { step(id, totalIn: totalIn, totalOut: totalOut) }
    }

    /// The final increment for a closed flow; forgets the flow.
    public func finish(_ id: UUID, totalIn: UInt64, totalOut: UInt64) -> Bytes {
        lock.withLock {
            defer { reported[id] = nil }
            return step(id, totalIn: totalIn, totalOut: totalOut)
        }
    }

    /// Caller holds the lock.
    private func step(_ id: UUID, totalIn: UInt64, totalOut: UInt64) -> Bytes {
        let last = reported[id] ?? (0, 0)
        reported[id] = (max(last.bytesIn, totalIn), max(last.bytesOut, totalOut))
        return Bytes(bytesIn: totalIn > last.bytesIn ? totalIn - last.bytesIn : 0,
                     bytesOut: totalOut > last.bytesOut ? totalOut - last.bytesOut : 0)
    }
}
