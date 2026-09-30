import SwiftUI
import TraceKit

struct DomainTableView: View {
    @ObservedObject var browser: BrowserModel
    @State private var sortOrder = [KeyPathComparator(\DomainSummary.lastSeen, order: .reverse)]

    var body: some View {
        Table(browser.domains.sorted(using: sortOrder), selection: $browser.selectedDomain, sortOrder: $sortOrder) {
            TableColumn("域名", value: \.domain) { row in
                HStack(spacing: 4) {
                    Text(row.domain).lineLimit(1)
                    if !row.resolved {
                        Label("未解析", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .width(min: 220, ideal: 320)
            TableColumn("连接数", value: \.connCount) { Text("\($0.connCount)").monospacedDigit() }
                .width(70)
            TableColumn("↓ 流量", value: \.bytesIn) { Text(Formatting.bytes($0.bytesIn)).monospacedDigit() }
                .width(80)
            TableColumn("↑ 流量", value: \.bytesOut) { Text(Formatting.bytes($0.bytesOut)).monospacedDigit() }
                .width(80)
            TableColumn("最近", value: \.lastSeen) { Text($0.lastSeen, style: .relative) }
                .width(90)
        }
        .overlay {
            if browser.domains.isEmpty {
                ContentUnavailableView("暂无记录", systemImage: "network",
                                       description: Text("所选时间范围内没有网络连接。"))
            }
        }
    }
}
