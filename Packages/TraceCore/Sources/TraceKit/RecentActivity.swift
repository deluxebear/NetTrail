import Foundation

public struct RecentApp: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public let displayName: String
    public let path: String
    public let lastSeen: Date
    /// Most recent first.
    public let domains: [String]
    /// Bytes per second over the rate window.
    public let rateIn: Double
    public let rateOut: Double
}

/// In-memory “last N minutes” view for the menu bar, with live transfer rates. Not thread-safe.
public final class RecentActivity {
    private struct Sample {
        let time: Date
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    private struct Entry {
        var app: ResolvedApp
        var domains: [String: Date]
        var samples: [Sample] = []
    }

    private let window: TimeInterval
    private let rateWindow: TimeInterval
    private var entries: [String: Entry] = [:]

    public init(window: TimeInterval = 300, rateWindow: TimeInterval = 10) {
        self.window = window
        self.rateWindow = rateWindow
    }

    public func record(app: ResolvedApp, domain: String, time: Date) {
        var entry = entries[app.key] ?? Entry(app: app, domains: [:])
        entry.app = app
        entry.domains[domain] = max(entry.domains[domain] ?? time, time)
        entries[app.key] = entry
    }

    /// Bytes moved on an open flow; also counts as activity on `domain`.
    public func recordTraffic(app: ResolvedApp, domain: String, time: Date, bytesIn: UInt64, bytesOut: UInt64) {
        record(app: app, domain: domain, time: time)
        entries[app.key]?.samples.append(Sample(time: time, bytesIn: bytesIn, bytesOut: bytesOut))
    }

    public func snapshot(now: Date, limit: Int = 8) -> [RecentApp] {
        let cutoff = now.addingTimeInterval(-window)
        let rateCutoff = now.addingTimeInterval(-rateWindow)
        for (key, var entry) in entries {
            entry.domains = entry.domains.filter { $0.value >= cutoff }
            entry.samples.removeAll { $0.time < rateCutoff }
            entries[key] = entry.domains.isEmpty ? nil : entry
        }
        return entries.values
            .map { entry in
                let sorted = entry.domains.sorted { $0.value > $1.value }
                let bytesIn = entry.samples.reduce(0.0) { $0 + Double($1.bytesIn) }
                let bytesOut = entry.samples.reduce(0.0) { $0 + Double($1.bytesOut) }
                return RecentApp(key: entry.app.key, displayName: entry.app.displayName, path: entry.app.path,
                                 lastSeen: sorted[0].value, domains: sorted.map(\.key),
                                 rateIn: bytesIn / rateWindow, rateOut: bytesOut / rateWindow)
            }
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(limit)
            .map { $0 }
    }
}
