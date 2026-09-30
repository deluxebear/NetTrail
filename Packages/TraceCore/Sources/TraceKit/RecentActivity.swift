import Foundation

public struct RecentApp: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public let displayName: String
    public let path: String
    public let lastSeen: Date
    /// Most recent first.
    public let domains: [String]
}

/// In-memory “last N minutes” view for the menu bar. Not thread-safe.
public final class RecentActivity {
    private struct Entry {
        var app: ResolvedApp
        var domains: [String: Date]
    }

    private let window: TimeInterval
    private var entries: [String: Entry] = [:]

    public init(window: TimeInterval = 300) {
        self.window = window
    }

    public func record(app: ResolvedApp, domain: String, time: Date) {
        var entry = entries[app.key] ?? Entry(app: app, domains: [:])
        entry.app = app
        entry.domains[domain] = max(entry.domains[domain] ?? time, time)
        entries[app.key] = entry
    }

    public func snapshot(now: Date, limit: Int = 8) -> [RecentApp] {
        let cutoff = now.addingTimeInterval(-window)
        for (key, var entry) in entries {
            entry.domains = entry.domains.filter { $0.value >= cutoff }
            entries[key] = entry.domains.isEmpty ? nil : entry
        }
        return entries.values
            .map { entry in
                let sorted = entry.domains.sorted { $0.value > $1.value }
                return RecentApp(key: entry.app.key, displayName: entry.app.displayName, path: entry.app.path,
                                 lastSeen: sorted[0].value, domains: sorted.map(\.key))
            }
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(limit)
            .map { $0 }
    }
}
