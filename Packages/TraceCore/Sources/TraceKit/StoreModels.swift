import Foundation
import TraceCore

public struct ResolvedApp: Hashable, Sendable {
    public let key: String
    public let displayName: String
    public let bundleID: String?
    public let path: String
    public let teamID: String?

    public init(key: String, displayName: String, bundleID: String?, path: String, teamID: String?) {
        self.key = key
        self.displayName = displayName
        self.bundleID = bundleID
        self.path = path
        self.teamID = teamID
    }
}

public enum StoreOp: Equatable, Sendable {
    case open(app: ResolvedApp, domain: String, resolved: Bool, source: HostSource, time: Date)
    case close(appKey: String, domain: String, time: Date, bytesIn: UInt64, bytesOut: UInt64)
}

public enum TimeRange: String, CaseIterable, Identifiable, Sendable {
    case today, last7Days, last30Days, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: "今天"
        case .last7Days: "7 天"
        case .last30Days: "30 天"
        case .all: "全部"
        }
    }

    public func startDate(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .today: calendar.startOfDay(for: now)
        case .last7Days: now.addingTimeInterval(-7 * 86_400)
        case .last30Days: now.addingTimeInterval(-30 * 86_400)
        case .all: nil
        }
    }
}

public struct AppSummary: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let key: String
    public let displayName: String
    public let bundleID: String?
    public let path: String?
    public let lastSeen: Date
    public let connCount: Int64
    public let bytesIn: Int64
    public let bytesOut: Int64
    public let domainCount: Int
}

public struct DomainSummary: Identifiable, Equatable, Sendable {
    public var id: String { domain }
    public let domain: String
    public let resolved: Bool
    public let lastSource: HostSource
    public let firstSeen: Date
    public let lastSeen: Date
    public let connCount: Int64
    public let bytesIn: Int64
    public let bytesOut: Int64
}

public struct HourPoint: Identifiable, Equatable, Sendable {
    public var id: Date { hour }
    public let hour: Date
    public let connCount: Int64
    public let bytesIn: Int64
    public let bytesOut: Int64
}
