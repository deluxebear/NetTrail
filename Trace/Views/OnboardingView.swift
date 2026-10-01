import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var extensionManager: ExtensionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Up NetTrail").font(.title2).bold()
            Text("NetTrail uses a content filter that only observes, never blocks, to record the domains each app connects to. Data stays on this Mac.")
                .foregroundStyle(.secondary)
            step(1, "Install the system extension", done: installed) {
                Button("Install") { extensionManager.install() }
            }
            step(2, "Approve it in System Settings", done: installed) {
                if extensionManager.extensionState == .needsApproval {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                }
            }
            step(3, "Enable the content filter", done: extensionManager.filterEnabled) {
                if installed {
                    Button("Enable") { Task { await extensionManager.enableFilter() } }
                }
            }
            if case .failed(let message) = extensionManager.extensionState {
                Text("Installation failed: \(message)").foregroundStyle(.red)
            }
            if let error = extensionManager.lastError {
                Text(error).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Later") { dismiss() }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!extensionManager.isReady)
            }
        }
        .padding(24)
        .frame(width: 460)
        .task { await extensionManager.refresh() }
    }

    private var installed: Bool { extensionManager.extensionState == .activated }

    private func step(_ number: Int, _ title: LocalizedStringKey, done: Bool, @ViewBuilder action: () -> some View) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title3)
            Text(title)
            Spacer()
            if !done { action() }
        }
    }
}
