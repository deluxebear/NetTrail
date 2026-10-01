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
                        GridRow { Text("First Seen").foregroundStyle(.secondary); Text(domain.firstSeen, format: .dateTime) }
                        GridRow { Text("Last Seen").foregroundStyle(.secondary); Text(domain.lastSeen, format: .dateTime) }
                        GridRow { Text("Domain Source").foregroundStyle(.secondary); Text(domain.lastSource.title) }
                        GridRow { Text("Connections").foregroundStyle(.secondary); Text("\(domain.connCount)") }
                        GridRow {
                            Text("Traffic").foregroundStyle(.secondary)
                            Text("↓ \(Formatting.bytes(domain.bytesIn))  ↑ \(Formatting.bytes(domain.bytesOut))")
                        }
                    }
                    Text("Last 7 Days (Hourly)").font(.headline)
                    Chart(browser.detailHours) { point in
                        BarMark(x: .value("Time", point.hour, unit: .hour),
                                y: .value("Connections", point.connCount))
                    }
                    .frame(height: 160)
                    if !browser.detailApps.isEmpty {
                        Text("Apps That Contacted This Domain").font(.headline)
                        ForEach(browser.detailApps) { app in
                            HStack {
                                AppIconView(path: app.path)
                                Text(app.displayName)
                                Spacer()
                                Text("\(app.connCount) connections").foregroundStyle(.secondary)
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
                            Text("Path").foregroundStyle(.secondary)
                            Text(app.path ?? String(localized: "Unknown")).textSelection(.enabled)
                        }
                        GridRow {
                            Text("Identifier").foregroundStyle(.secondary)
                            Text(app.key).textSelection(.enabled)
                        }
                        GridRow { Text("Last Active").foregroundStyle(.secondary); Text(app.lastSeen, format: .dateTime) }
                    }
                    OriginList(origins: browser.detailOrigins, showsApp: false)
                }
                .padding()
            }
        } else {
            ContentUnavailableView("Select a Domain", systemImage: "cursorarrow.click")
        }
    }
}

/// Who launched the connecting process: responsible app, interpreter script and parent chain.
private struct OriginList: View {
    let origins: [OriginSummary]
    let showsApp: Bool

    var body: some View {
        if !origins.isEmpty {
            Text("Launched By").font(.headline)
            ForEach(origins) { origin in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if showsApp {
                            AppIconView(path: origin.appPath)
                            Text(origin.appName)
                            Text("·").foregroundStyle(.secondary)
                        }
                        if origin.via.isEmpty {
                            Text("Run directly").foregroundStyle(.secondary)
                        } else {
                            AppIconView(path: origin.viaPath)
                            Text("via \(origin.via)")
                        }
                        Spacer()
                        Text("\(origin.connCount) connections").foregroundStyle(.secondary)
                    }
                    if !origin.script.isEmpty {
                        Text("Script: \(origin.script)")
                            .font(.caption.monospaced()).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle)
                    }
                    if !origin.chain.isEmpty {
                        Text("Process chain: \(origin.chain)")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
