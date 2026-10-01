import SwiftUI
import TraceKit

struct DomainTableView: View {
    @ObservedObject var browser: BrowserModel
    @State private var sortOrder = [KeyPathComparator(\DomainSummary.lastSeen, order: .reverse)]

    var body: some View {
        // `Text(_, style: .relative)` re-lays out every row each second; a 30-second tick is plenty here.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            table(now: context.date)
        }
        .overlay {
            if browser.domains.isEmpty {
                ContentUnavailableView("No Records", systemImage: "network",
                                       description: Text("No network connections in the selected time range."))
            }
        }
    }

    private func table(now: Date) -> some View {
        Table(browser.domains.sorted(using: sortOrder), selection: $browser.selectedDomain, sortOrder: $sortOrder) {
            TableColumn("Domain", value: \.domain) { row in
                HStack(spacing: 4) {
                    Text(row.domain).lineLimit(1)
                    if !row.resolved {
                        Label("Unresolved", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .width(min: 220, ideal: 320)
            TableColumn("Connections", value: \.connCount) { Text("\($0.connCount)").monospacedDigit() }
                .width(70)
            TableColumn("↓ Traffic", value: \.bytesIn) { Text(Formatting.bytes($0.bytesIn)).monospacedDigit() }
                .width(80)
            TableColumn("↑ Traffic", value: \.bytesOut) { Text(Formatting.bytes($0.bytesOut)).monospacedDigit() }
                .width(80)
            TableColumn("Last Seen", value: \.lastSeen) { Text(Formatting.relative($0.lastSeen, now: now)) }
                .width(90)
        }
    }
}
