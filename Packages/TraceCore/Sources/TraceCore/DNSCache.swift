import Foundation

/// Thread-safe IP → domain map built from observed DNS responses.
public final class DNSCache: @unchecked Sendable {
    private struct Entry {
        let host: String
        let expires: Date
    }

    private let capacity: Int
    private let minTTL: TimeInterval
    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    /// `minTTL` extends short DNS TTLs: apps often connect after the record's TTL.
    public init(capacity: Int = 20_000, minTTL: TimeInterval = 300) {
        self.capacity = capacity
        self.minTTL = minTTL
    }

    public var count: Int { lock.withLock { entries.count } }

    public func insert(ip: String, host: String, ttl: UInt32, now: Date) {
        guard let key = IPAddressText.normalize(ip) else { return }
        let expires = now.addingTimeInterval(max(TimeInterval(ttl), minTTL))
        lock.withLock {
            entries[key] = Entry(host: host, expires: expires)
            if entries.count > capacity { evict(now: now) }
        }
    }

    public func lookup(ip: String, now: Date) -> String? {
        guard let key = IPAddressText.normalize(ip) else { return nil }
        return lock.withLock {
            guard let entry = entries[key] else { return nil }
            guard entry.expires > now else {
                entries[key] = nil
                return nil
            }
            return entry.host
        }
    }

    /// Caller holds the lock. Drops expired entries, then the earliest-expiring down to 90% capacity.
    private func evict(now: Date) {
        entries = entries.filter { $0.value.expires > now }
        let target = capacity * 9 / 10
        guard entries.count > target else { return }
        let victims = entries.sorted { $0.value.expires < $1.value.expires }.prefix(entries.count - target)
        for (key, _) in victims { entries[key] = nil }
    }
}
