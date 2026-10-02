import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var extensionManager: ExtensionManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage(UpdateChecker.enabledKey) private var checkForUpdates = true
    @State private var confirmClear = false
    @State private var confirmUninstall = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                    .onChange(of: checkForUpdates) { _, _ in Task { await model.updates.check() } }
                if let loginError { Text(loginError).foregroundStyle(.red).font(.caption) }
                Stepper("Keep history for \(model.retentionDays) days", value: $model.retentionDays, in: 1...365)
            }
            Section("Data") {
                Button("Clear All Data…", role: .destructive) { confirmClear = true }
            }
            Section("Extension") {
                LabeledContent("Status", value: extensionStatusText)
                Button("Uninstall Extension…", role: .destructive) { confirmUninstall = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Clear all records? This can’t be undone.", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { Task { await model.clearAllData() } }
        }
        .confirmationDialog("Recording stops once the extension is uninstalled.", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { Task { await extensionManager.uninstall() } }
        }
    }

    private var extensionStatusText: String {
        switch extensionManager.extensionState {
        case .unknown: String(localized: "Unknown")
        case .notInstalled: String(localized: "Not installed")
        case .needsApproval: String(localized: "Awaiting approval")
        case .activated: extensionManager.filterEnabled ? String(localized: "Running") : String(localized: "Installed, filter not enabled")
        case .failed(let message): String(localized: "Failed: \(message)")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = String(localized: "Couldn’t change the setting: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
