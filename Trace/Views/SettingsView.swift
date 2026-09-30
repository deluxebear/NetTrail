import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var extensionManager: ExtensionManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmClear = false
    @State private var confirmUninstall = false

    var body: some View {
        Form {
            Section("常规") {
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError { Text(loginError).foregroundStyle(.red).font(.caption) }
                Stepper("历史保留 \(model.retentionDays) 天", value: $model.retentionDays, in: 1...365)
            }
            Section("数据") {
                Button("清空所有数据…", role: .destructive) { confirmClear = true }
            }
            Section("扩展") {
                LabeledContent("状态", value: extensionStatusText)
                Button("卸载扩展…", role: .destructive) { confirmUninstall = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("清空所有记录？此操作无法撤销。", isPresented: $confirmClear) {
            Button("清空", role: .destructive) { model.clearAllData() }
        }
        .confirmationDialog("卸载扩展后将停止记录。", isPresented: $confirmUninstall) {
            Button("卸载", role: .destructive) { Task { await extensionManager.uninstall() } }
        }
    }

    private var extensionStatusText: String {
        switch extensionManager.extensionState {
        case .unknown: "未知"
        case .notInstalled: "未安装"
        case .needsApproval: "等待批准"
        case .activated: extensionManager.filterEnabled ? "运行中" : "已安装，过滤未启用"
        case .failed(let message): "失败：\(message)"
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "设置失败：\(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
