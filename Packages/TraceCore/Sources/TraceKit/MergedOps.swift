import Foundation
import TraceCore

/// Store ops folded by row key, so a batch writes each app, domain and hour bucket once.
/// Later ops win for metadata (name, path, source); times take min/max; counters add, saturating.
struct MergedOps {
    struct DomainKey: Hashable {
        let appKey: String
        let domain: String
    }

    struct HourKey: Hashable {
        let appKey: String
        let domain: String
        let hour: Int64
    }

    struct AppRow {
        var app: ResolvedApp
        var firstSeen: Date
        var lastSeen: Date
    }

    struct DomainOpen {
        var resolved: Bool
        var source: HostSource
        var firstSeen: Date
        var lastSeen: Date
        var count: Int64
    }

    struct DomainClose {
        var lastSeen: Date
        var bytesIn: Int64
        var bytesOut: Int64
    }

    struct OriginKey: Hashable {
        let appKey: String
        let domain: String
        let via: String
        let script: String
    }

    struct OriginRow {
        var viaPath: String?
        var chain: String
        var firstSeen: Date
        var lastSeen: Date
        var count: Int64
    }

    struct HourCounts {
        var conn: Int64 = 0
        var bytesIn: Int64 = 0
        var bytesOut: Int64 = 0
    }

    private(set) var apps: [String: AppRow] = [:]
    private(set) var opens: [DomainKey: DomainOpen] = [:]
    private(set) var closes: [DomainKey: DomainClose] = [:]
    /// Latest close time per app key, for `app.last_seen`.
    private(set) var appCloses: [String: Date] = [:]
    private(set) var hours: [HourKey: HourCounts] = [:]
    private(set) var origins: [OriginKey: OriginRow] = [:]

    init(_ ops: [StoreOp]) {
        for op in ops {
            switch op {
            case let .open(app, domain, resolved, source, time, origin):
                if var row = apps[app.key] {
                    row.app = app
                    row.firstSeen = min(row.firstSeen, time)
                    row.lastSeen = max(row.lastSeen, time)
                    apps[app.key] = row
                } else {
                    apps[app.key] = AppRow(app: app, firstSeen: time, lastSeen: time)
                }
                let key = DomainKey(appKey: app.key, domain: domain)
                if var open = opens[key] {
                    open.resolved = resolved
                    open.source = source
                    open.firstSeen = min(open.firstSeen, time)
                    open.lastSeen = max(open.lastSeen, time)
                    open.count += 1
                    opens[key] = open
                } else {
                    opens[key] = DomainOpen(resolved: resolved, source: source, firstSeen: time, lastSeen: time, count: 1)
                }
                hours[HourKey(appKey: app.key, domain: domain, hour: Store.hour(time)), default: HourCounts()].conn += 1
                if let origin {
                    let originKey = OriginKey(appKey: app.key, domain: domain, via: origin.via, script: origin.script)
                    if var row = origins[originKey] {
                        row.viaPath = origin.viaPath
                        row.chain = origin.chain
                        row.firstSeen = min(row.firstSeen, time)
                        row.lastSeen = max(row.lastSeen, time)
                        row.count += 1
                        origins[originKey] = row
                    } else {
                        origins[originKey] = OriginRow(viaPath: origin.viaPath, chain: origin.chain,
                                                       firstSeen: time, lastSeen: time, count: 1)
                    }
                }
            case let .close(appKey, domain, time, bytesIn, bytesOut):
                let inBytes = Int64(clamping: bytesIn)
                let outBytes = Int64(clamping: bytesOut)
                let key = DomainKey(appKey: appKey, domain: domain)
                if var close = closes[key] {
                    close.lastSeen = max(close.lastSeen, time)
                    close.bytesIn = Self.add(close.bytesIn, inBytes)
                    close.bytesOut = Self.add(close.bytesOut, outBytes)
                    closes[key] = close
                } else {
                    closes[key] = DomainClose(lastSeen: time, bytesIn: inBytes, bytesOut: outBytes)
                }
                appCloses[appKey] = max(appCloses[appKey] ?? time, time)
                let hourKey = HourKey(appKey: appKey, domain: domain, hour: Store.hour(time))
                var counts = hours[hourKey] ?? HourCounts()
                counts.bytesIn = Self.add(counts.bytesIn, inBytes)
                counts.bytesOut = Self.add(counts.bytesOut, outBytes)
                hours[hourKey] = counts
            }
        }
    }

    private static func add(_ a: Int64, _ b: Int64) -> Int64 {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? .max : sum
    }
}
