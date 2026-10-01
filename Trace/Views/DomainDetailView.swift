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
                    OriginList(origins: browser.detailOrigins, showsApp: browser.selectedAppID == nil)
                }
                .padding()
            }
        } else if let app = browser.selectedApp {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        AppIconView(path: app.path, size: 32)
                        Text(app.displayName).font(.title3).bold()
                    }
                    Grid(alignment: .leading, verticalSpacing: 4) {
                        GridRow {
                            Text("路径").foregroundStyle(.secondary)
                            Text(app.path ?? "未知").textSelection(.enabled)
                        }
                        GridRow {
                            Text("标识").foregroundStyle(.secondary)
                            Text(app.key).textSelection(.enabled)
                        }
                        GridRow { Text("最近活动").foregroundStyle(.secondary); Text(app.lastSeen, format: .dateTime) }
                    }
                    OriginList(origins: browser.detailOrigins, showsApp: false)
                }
                .padding()
            }
        } else {
            ContentUnavailableView("选择一个域名", systemImage: "cursorarrow.click")
        }
    }
}

/// Who launched the connecting process: responsible app, interpreter script and parent chain.
private struct OriginList: View {
    let origins: [OriginSummary]
    let showsApp: Bool

    var body: some View {
        if !origins.isEmpty {
            Text("调用来源").font(.headline)
            ForEach(origins) { origin in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if showsApp {
                            AppIconView(path: origin.appPath)
                            Text(origin.appName)
                            Text("·").foregroundStyle(.secondary)
                        }
                        if origin.via.isEmpty {
                            Text("直接运行").foregroundStyle(.secondary)
                        } else {
                            AppIconView(path: origin.viaPath)
                            Text("经由 \(origin.via)")
                        }
                        Spacer()
                        Text("\(origin.connCount) 次").foregroundStyle(.secondary)
                    }
                    if !origin.script.isEmpty {
                        Text("脚本：\(origin.script)")
                            .font(.caption.monospaced()).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle)
                    }
                    if !origin.chain.isEmpty {
                        Text("进程链：\(origin.chain)")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
