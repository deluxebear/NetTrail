import Foundation
import TraceCore
import TraceKit

/// Live menu bar activity. Separate from `AppModel` because its rates change every second,
/// and views observing `AppModel` (the main window) must not re-render that often.
@MainActor
final class RecentFeed: ObservableObject {
    @Published fileprivate(set) var apps: [RecentApp] = []
}

@MainActor
final class AppModel: ObservableObject {
    enum MonitorStatus { case needsSetup, disconnected, paused, monitoring }

    private static let batchSize = 5000
    private static let retentionKey = "retentionDays"

    let extensionManager: ExtensionManager
    let store: Store
    private let ingestor: Ingestor
    private let connection: FilterConnection

    let recent = RecentFeed()
    @Published private(set) var isConnected = false
    @Published private(set) var droppedTotal: UInt64 = 0
    @Published private(set) var dataVersion = 0
    @Published private(set) var storeBackupURL: URL?
    @Published private(set) var writeError: String?
    @Published var focusAppKey: String?
    @Published var isPaused = false
    @Published var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: Self.retentionKey)
            Task { await purgeOldHistory() }
        }
    }

    private var started = false

    init(store: Store, storeBackupURL: URL?, connection: FilterConnection, extensionManager: ExtensionManager) {
        self.store = store
        self.storeBackupURL = storeBackupURL
        self.connection = connection
        self.extensionManager = extensionManager
        ingestor = Ingestor(store: store)
        let saved = UserDefaults.standard.integer(forKey: Self.retentionKey)
        retentionDays = saved > 0 ? saved : 30
    }

    static func live() -> AppModel {
        let fm = FileManager.default
        let directory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Trace", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let store: Store
        let backup: URL?
        do {
            (store, backup) = try Store.openRecovering(at: directory.appendingPathComponent("trace.sqlite"))
        } catch {
            // Last resort: keep the app usable for this session.
            store = try! Store.inMemory()
            backup = nil
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let connection = FilterConnection(
            machServiceName: info["TraceFilterMachService"] as? String ?? "",
            teamID: info["TraceTeamID"] as? String ?? "")
        return AppModel(store: store, storeBackupURL: backup, connection: connection,
                        extensionManager: ExtensionManager())
    }

    var status: MonitorStatus {
        if !extensionManager.isReady { return .needsSetup }
        if !isConnected { return .disconnected }
        return isPaused ? .paused : .monitoring
    }

    var menuBarSymbol: String {
        switch status {
        case .monitoring: "network"
        case .paused: "pause.circle"
        case .needsSetup, .disconnected: "exclamationmark.triangle"
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        await extensionManager.refresh()
        await purgeOldHistory()
        Task { await pollLoop() }
        Task { await purgeLoop() }
    }

    func clearAllData() async {
        do {
            try await ingestor.deleteAll()
            dataVersion &+= 1
        } catch {
            writeError = String(localized: "Failed to clear data: \(error.localizedDescription)")
        }
    }

    private func pollLoop() async {
        var backoff: Double = 1
        while !Task.isCancelled {
            let batch: EventBatch
            do {
                batch = try await connection.fetch(maxCount: Self.batchSize)
            } catch {
                update(\.isConnected, false)
                update(\.recent.apps, await ingestor.recent(now: Date()))
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 30)
                continue
            }
            update(\.isConnected, true)
            backoff = 1
            let result = await ingestor.ingest(batch, paused: isPaused, now: Date())
            update(\.writeError, result.error.map { String(localized: "Failed to write to the database: \($0.localizedDescription)") })
            update(\.droppedTotal, result.droppedTotal)
            update(\.recent.apps, result.recent)
            if !batch.events.isEmpty { dataVersion &+= 1 }
            if batch.events.count < Self.batchSize {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func purgeLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(86_400))
            await purgeOldHistory()
        }
    }

    private func purgeOldHistory() async {
        try? await ingestor.purge(before: Date().addingTimeInterval(-Double(retentionDays) * 86_400))
    }

    /// @Published notifies on every assignment, so skip unchanged values to avoid needless view updates.
    private func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppModel, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
