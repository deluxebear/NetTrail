import SwiftUI

@main
struct TraceApp: App {
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
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
            .task {
                await model.start()
                if !extensionManager.isReady {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}

// Placeholder; replaced by Views/MainWindow.swift in Task 11.
struct MainWindow: View {
    var body: some View { Text("Trace") }
}
