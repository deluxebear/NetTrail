import SwiftUI

extension Notification.Name {
    static let traceShowMainWindow = Notification.Name("TraceShowMainWindow")
}

/// Launching Trace again (Finder, Spotlight, `open`) while it runs shows the main window,
/// since a menu bar app has no Dock icon to click.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: .traceShowMainWindow, object: nil)
        return true
    }
}

@main
struct TraceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(model.recent)
                .environmentObject(model.extensionManager)
        } label: {
            MenuBarLabel()
                .environmentObject(model)
                .environmentObject(model.extensionManager)
        }
        .menuBarExtraStyle(.window)

        Window("Trace", id: "main") {
            MainWindow()
                .environmentObject(model)
                .environmentObject(model.extensionManager)
        }
        .defaultSize(width: 1100, height: 680)
    }
}

/// Always rendered at launch, so it starts the model and opens onboarding when setup is needed.
private struct MenuBarLabel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var extensionManager: ExtensionManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.menuBarSymbol)
            .task { await model.start() }
            // The extension state arrives asynchronously after launch; open setup only once it is known.
            .onChange(of: extensionManager.needsSetup, initial: true) { _, needsSetup in
                if needsSetup { showMain() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .traceShowMainWindow)) { _ in showMain() }
    }

    private func showMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
