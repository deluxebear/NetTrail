import SwiftUI
import TraceCore

enum Formatting {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
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
