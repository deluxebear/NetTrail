import Charts
import SwiftUI
import TraceKit

struct DomainDetailView: View {
    @ObservedObject var browser: BrowserModel

    var body: some View {
        if let domainName = browser.selectedDomain,
           let domain = browser.domains.first(where: { $0.domain == domainName }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(domain.domain).font(.title3).bold().textSelection(.enabled)
                    Grid(alignment: .leading, verticalSpacing: 4) {
                        GridRow { Text("首次访问").foregroundStyle(.secondary); Text(domain.firstSeen, format: .dateTime) }
                        GridRow { Text("最近访问").foregroundStyle(.secondary); Text(domain.lastSeen, format: .dateTime) }
                        GridRow { Text("域名来源").foregroundStyle(.secondary); Text(domain.lastSource.title) }
                        GridRow { Text("连接数").foregroundStyle(.secondary); Text("\(domain.connCount)") }
                        GridRow {
                            Text("流量").foregroundStyle(.secondary)
                            Text("↓ \(Formatting.bytes(domain.bytesIn))  ↑ \(Formatting.bytes(domain.bytesOut))")
                        }
                    }
                    Text("近 7 天（按小时）").font(.headline)
                    Chart(browser.detailHours) { point in
                        BarMark(x: .value("时间", point.hour, unit: .hour),
                                y: .value("连接数", point.connCount))
                    }
                    .frame(height: 160)
                    if !browser.detailApps.isEmpty {
                        Text("访问过该域名的 App").font(.headline)
                        ForEach(browser.detailApps) { app in
                            HStack {
                                AppIconView(path: app.path)
                                Text(app.displayName)
                                Spacer()
                                Text("\(app.connCount) 次").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
        } else {
            ContentUnavailableView("选择一个域名", systemImage: "cursorarrow.click")
        }
    }
}
