import Foundation

/// Thread-safe bounded FIFO. When full, the oldest event is dropped and counted.
public final class EventRing: @unchecked Sendable {
    public let capacity: Int
    private var storage: [FlowEvent?]
    private var head = 0
    private var size = 0
    private var dropped: UInt64 = 0
    private let lock = NSLock()

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    public var count: Int { lock.withLock { size } }

    public func append(_ event: FlowEvent) {
        lock.withLock {
            if size == capacity {
                storage[head] = nil
                head = (head + 1) % capacity
                size -= 1
                dropped += 1
            }
            storage[(head + size) % capacity] = event
            size += 1
        }
    }

    /// Removes up to `max` oldest events; the batch reports drops since the previous drain.
    public func drain(max: Int) -> EventBatch {
        lock.withLock {
            let n = Swift.min(Swift.max(max, 0), size)
            var events: [FlowEvent] = []
            events.reserveCapacity(n)
            for i in 0..<n {
                let index = (head + i) % capacity
                if let event = storage[index] { events.append(event) }
                storage[index] = nil
            }
            head = (head + n) % capacity
            size -= n
            let reported = dropped
            dropped = 0
            return EventBatch(events: events, droppedSinceLastBatch: reported)
        }
    }
}
