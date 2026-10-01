import SwiftUI
import TraceKit

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var extensionManager: ExtensionManager
    @EnvironmentObject private var recent: RecentFeed
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var expandedKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if model.status == .needsSetup || model.status == .disconnected {
                Button("Fix…") { openMain() }
            }
            if model.droppedTotal > 0 {
                Text("\(model.droppedTotal) events dropped").font(.caption).foregroundStyle(.orange)
            }
            Text("Last 5 Minutes").font(.caption).foregroundStyle(.secondary)
            if recent.apps.isEmpty {
                Text("No network activity").foregroundStyle(.secondary).padding(.vertical, 4)
            }
            ForEach(recent.apps) { app in
                row(app)
            }
            Divider()
            HStack {
                Button("Open Main Window") { openMain() }
                Button(model.isPaused ? "Resume Recording" : "Pause Recording") { model.isPaused.toggle() }
                Spacer()
                Button("Settings", systemImage: "gearshape") {
                    dismiss()
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .labelStyle(.iconOnly)
                .help("Settings")
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Text("NetTrail").font(.headline)
            if totalRateIn + totalRateOut >= 1 {
                Text("↓ \(Formatting.rate(totalRateIn))  ↑ \(Formatting.rate(totalRateOut))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(model.status.color).frame(width: 8, height: 8)
            Text(model.status.title).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(_ app: RecentApp) -> some View {
        Button {
            expandedKey = expandedKey == app.key ? nil : app.key
        } label: {
            HStack {
                AppIconView(path: app.path)
                Text(app.displayName).lineLimit(1)
                Spacer()
                if app.rateIn + app.rateOut >= 1 {
                    Text("↓ \(Formatting.rate(app.rateIn))").monospacedDigit().foregroundStyle(.secondary)
                }
                Text("\(app.domains.count) domains").foregroundStyle(.secondary)
                Image(systemName: expandedKey == app.key ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if expandedKey == app.key {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(app.domains.prefix(10), id: \.self) { domain in
                    Text(domain).font(.caption).lineLimit(1)
                }
                Button("Show in Main Window") {
                    model.focusAppKey = app.key
                    openMain()
                }
                .font(.caption)
            }
            .padding(.leading, 24)
        }
    }

    private var totalRateIn: Double { recent.apps.reduce(0) { $0 + $1.rateIn } }
    private var totalRateOut: Double { recent.apps.reduce(0) { $0 + $1.rateOut } }

    private func openMain() {
        // The .window-style MenuBarExtra panel does not close on its own when another window opens.
        dismiss()
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
