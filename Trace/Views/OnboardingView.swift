import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var extensionManager: ExtensionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置 Trace").font(.title2).bold()
            Text("Trace 使用一个只观察、不拦截的内容过滤器来记录各 App 访问的域名。数据只保存在本机。")
                .foregroundStyle(.secondary)
            step(1, "安装系统扩展", done: installed) {
                Button("安装") { extensionManager.install() }
            }
            step(2, "在系统设置中批准", done: installed) {
                if extensionManager.extensionState == .needsApproval {
                    Button("打开系统设置") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                }
            }
            step(3, "启用内容过滤", done: extensionManager.filterEnabled) {
                if installed {
                    Button("启用") { Task { await extensionManager.enableFilter() } }
                }
            }
            if case .failed(let message) = extensionManager.extensionState {
                Text("安装失败：\(message)").foregroundStyle(.red)
            }
            if let error = extensionManager.lastError {
                Text(error).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("稍后") { dismiss() }
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!extensionManager.isReady)
            }
        }
        .padding(24)
        .frame(width: 460)
        .task { await extensionManager.refresh() }
    }

    private var installed: Bool { extensionManager.extensionState == .activated }

    private func step(_ number: Int, _ title: String, done: Bool, @ViewBuilder action: () -> some View) -> some View {
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
