import SwiftUI
import TraceCore

enum Formatting {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
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
        case .system: "系统提供"
        case .sni: "TLS SNI"
        case .httpHost: "HTTP Host"
        case .dnsCache: "DNS 缓存"
        case .none: "未解析"
        }
    }
}

extension AppModel.MonitorStatus {
    var title: String {
        switch self {
        case .monitoring: "监控中"
        case .paused: "已暂停"
        case .needsSetup: "需要设置"
        case .disconnected: "扩展未连接"
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
