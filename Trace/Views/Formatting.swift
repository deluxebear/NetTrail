import SwiftUI
import TraceCore

enum Formatting {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond.rounded()), countStyle: .file) + "/s"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// “3 min. ago” relative to `now`; dates newer than `now` read as now.
    static func relative(_ date: Date, now: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: max(now, date))
    }

    /// Containing folder with the home directory shown as `~`, e.g. `~/.hermes/node/bin`.
    static func location(_ path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        let home = NSHomeDirectory()
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }
}

extension HostSource {
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .sni: "TLS SNI"
        case .httpHost: "HTTP Host"
        case .dnsCache: String(localized: "DNS cache")
        case .none: String(localized: "Unresolved")
        }
    }
}

extension AppModel.MonitorStatus {
    var title: String {
        switch self {
        case .monitoring: String(localized: "Monitoring")
        case .paused: String(localized: "Paused")
        case .needsSetup: String(localized: "Needs setup")
        case .disconnected: String(localized: "Extension not connected")
        }
    }

    var color: Color {
        switch self {
        case .monitoring: .green
        case .paused: .secondary
        case .needsSetup, .disconnected: .orange
        }
    }
}
