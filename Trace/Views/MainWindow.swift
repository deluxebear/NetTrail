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
    @State private var showOnboarding = false

    init(browser: @autoclosure @escaping () -> BrowserModel) {
        _browser = StateObject(wrappedValue: browser())
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if browser.selection == .settings {
                SettingsView()
            } else {
                DomainTableView(browser: browser)
                    .navigationSplitViewColumnWidth(min: 420, ideal: 620)
            }
        } detail: {
            DomainDetailView(browser: browser)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        }
        .toolbar {
            ToolbarItem {
                Picker("时间范围", selection: $browser.range) {
                    ForEach(TimeRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .safeAreaInset(edge: .top) { banners }
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
        .onAppear {
            browser.reload()
            showOnboarding = !extensionManager.isReady
            if let key = model.focusAppKey { browser.focus(appKey: key); model.focusAppKey = nil }
        }
        .onReceive(model.$dataVersion.throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)) { _ in
            browser.reload()
        }
        .onChange(of: model.focusAppKey) { _, key in
            guard let key else { return }
            browser.focus(appKey: key)
            model.focusAppKey = nil
        }
        .onChange(of: extensionManager.isReady) { _, ready in
            if !ready { showOnboarding = true }
        }
    }

    private var sidebar: some View {
        List(selection: $browser.selection) {
            Label("全部 App", systemImage: "square.grid.2x2").tag(BrowserModel.SidebarItem.allApps)
            Section("App") {
                ForEach(browser.filteredApps) { app in
                    HStack {
                        AppIconView(path: app.path, size: 18)
                        VStack(alignment: .leading) {
                            Text(app.displayName).lineLimit(1)
                            Text("\(app.domainCount) 个域名 · \(Formatting.bytes(app.bytesIn + app.bytesOut))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(BrowserModel.SidebarItem.app(app.id))
                }
            }
            Label("设置", systemImage: "gearshape").tag(BrowserModel.SidebarItem.settings)
        }
        .searchable(text: $browser.search, placement: .sidebar, prompt: "搜索 App")
        .safeAreaInset(edge: .bottom) {
            Picker("排序", selection: $browser.appSort) {
                ForEach(BrowserModel.AppSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 4) {
            if let backup = model.storeBackupURL {
                banner("数据库无法打开，已备份到 \(backup.lastPathComponent) 并新建空数据库。")
            }
            if let error = model.writeError ?? browser.errorText {
                banner(error)
            }
            if model.status == .disconnected {
                banner("扩展未连接，正在重试…")
            }
            if model.droppedTotal > 0 {
                banner("有 \(model.droppedTotal) 条事件因缓冲区已满而丢失。")
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

// Placeholders; replaced by Views/OnboardingView.swift and Views/SettingsView.swift in Task 12.
struct OnboardingView: View { var body: some View { Text("Onboarding") } }
struct SettingsView: View { var body: some View { Text("Settings") } }
