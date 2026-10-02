import Combine
import SwiftUI
import TraceKit

struct MainWindow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var extensionManager: ExtensionManager

    var body: some View {
        MainWindowContent(browser: BrowserModel(store: model.store))
    }
}

private struct MainWindowContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var extensionManager: ExtensionManager
    @StateObject var browser: BrowserModel
    @Environment(\.openSettings) private var openSettings
    @State private var showOnboarding = false

    init(browser: @autoclosure @escaping () -> BrowserModel) {
        _browser = StateObject(wrappedValue: browser())
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            VStack(spacing: 0) {
                banners
                DomainTableView(browser: browser)
            }
            .navigationSplitViewColumnWidth(min: 420, ideal: 620)
        } detail: {
            DomainDetailView(browser: browser)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        }
        .toolbar {
            ToolbarItem {
                Picker("Time Range", selection: $browser.range) {
                    ForEach(TimeRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button("Settings", systemImage: "gearshape") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .help("Settings (⌘,)")
            }
            ToolbarItem { UpdateButton(checker: model.updates) }
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
        .onAppear {
            browser.reload()
            showOnboarding = extensionManager.needsSetup
            if let key = model.focusAppKey { browser.focus(appKey: key); model.focusAppKey = nil }
        }
        // Traffic updates arrive every second; reloading re-lays out the whole table, so cap it.
        .onReceive(model.$dataVersion.throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)) { _ in
            browser.reload()
        }
        .onChange(of: model.focusAppKey) { _, key in
            guard let key else { return }
            browser.focus(appKey: key)
            model.focusAppKey = nil
        }
        .onChange(of: extensionManager.needsSetup) { _, needsSetup in
            if needsSetup { showOnboarding = true }
        }
    }

    private var sidebar: some View {
        List(selection: $browser.selection) {
            Label("All Apps", systemImage: "square.grid.2x2").tag(BrowserModel.SidebarItem.allApps)
            Section("App") {
                let ambiguous = browser.ambiguousNames
                ForEach(browser.filteredApps) { app in
                    HStack {
                        AppIconView(path: app.path, size: 18)
                        VStack(alignment: .leading) {
                            Text(app.displayName).lineLimit(1)
                            if ambiguous.contains(app.displayName), let path = app.path {
                                Text(Formatting.location(path))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Text("\(app.domainCount) domains · \(Formatting.bytes(app.bytesIn + app.bytesOut))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .help(app.path ?? app.key)
                    .contextMenu {
                        Menu("Copy Connections (Excluding LAN)") {
                            ForEach(ProxyRuleFormat.allCases) { format in
                                Button(format.title) { copyRules(appID: app.id, format: format) }
                            }
                        }
                    }
                    .tag(BrowserModel.SidebarItem.app(app.id))
                }
            }
        }
        .searchable(text: $browser.search, placement: .sidebar, prompt: "Search Apps")
        .safeAreaInset(edge: .bottom) {
            Picker("Sort", selection: $browser.appSort) {
                ForEach(BrowserModel.AppSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
    }

    private func copyRules(appID: Int64, format: ProxyRuleFormat) {
        let rules = browser.proxyRules(appID: appID, format: format)
        guard !rules.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rules + "\n", forType: .string)
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 4) {
            if let backup = model.storeBackupURL {
                banner(String(localized: "The database couldn’t be opened. It was backed up to \(backup.lastPathComponent) and a new empty database was created."))
            }
            if let error = model.writeError ?? browser.errorText {
                banner(error)
            }
            if model.status == .disconnected {
                banner(String(localized: "Extension not connected. Retrying…"))
            }
            if model.droppedTotal > 0 {
                banner(String(localized: "\(model.droppedTotal) events were dropped because the buffer was full."))
            }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.orange.opacity(0.15))
    }
}

/// Shown in the toolbar only while a newer release exists; opens its release page.
private struct UpdateButton: View {
    @ObservedObject var checker: UpdateChecker
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let update = checker.available {
            Button("Update Available: \(update.version)", systemImage: "arrow.down.circle.fill") {
                openURL(update.url)
            }
            .foregroundStyle(.tint)
            .help("A new version of NetTrail is available. Click to open the download page.")
        }
    }
}
