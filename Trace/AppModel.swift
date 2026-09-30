import Foundation
import TraceCore
import TraceKit

@MainActor
final class AppModel: ObservableObject {
    enum MonitorStatus { case needsSetup, disconnected, paused, monitoring }

    private static let batchSize = 5000
    private static let retentionKey = "retentionDays"

    let extensionManager: ExtensionManager
    let store: Store
    private let aggregator: Aggregator
    private let connection: FilterConnection

    @Published private(set) var recent: [RecentApp] = []
    @Published private(set) var isConnected = false
    @Published private(set) var droppedTotal: UInt64 = 0
    @Published private(set) var dataVersion = 0
    @Published private(set) var storeBackupURL: URL?
    @Published private(set) var writeError: String?
    @Published var focusAppKey: String?
    @Published var isPaused = false {
        didSet { aggregator.isPaused = isPaused }
    }
    @Published var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: Self.retentionKey)
            purgeOldHistory()
        }
    }

    private var started = false

    init(store: Store, storeBackupURL: URL?, connection: FilterConnection, extensionManager: ExtensionManager) {
        self.store = store
        self.storeBackupURL = storeBackupURL
        self.connection = connection
        self.extensionManager = extensionManager
        let resolver = AppIdentityResolver()
        aggregator = Aggregator(store: store) { resolver.resolve($0) }
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
        purgeOldHistory()
        Task { await pollLoop() }
        Task { await purgeLoop() }
    }

    func clearAllData() {
        do {
            try store.deleteAll()
            dataVersion &+= 1
        } catch {
            writeError = "清空数据失败：\(error.localizedDescription)"
        }
    }

    private func pollLoop() async {
        var backoff: Double = 1
        while !Task.isCancelled {
            let batch: EventBatch
            do {
                batch = try await connection.fetch(maxCount: Self.batchSize)
            } catch {
                isConnected = false
                recent = aggregator.recent.snapshot(now: Date())
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 30)
                continue
            }
            isConnected = true
            backoff = 1
            do {
                try aggregator.ingest(batch, now: Date())
                writeError = nil
            } catch {
                writeError = "写入数据库失败：\(error.localizedDescription)"
            }
            droppedTotal = aggregator.droppedTotal
            if !batch.events.isEmpty { dataVersion &+= 1 }
            recent = aggregator.recent.snapshot(now: Date())
            if batch.events.count < Self.batchSize {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func purgeLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(86_400))
            purgeOldHistory()
        }
    }

    private func purgeOldHistory() {
        try? store.purge(before: Date().addingTimeInterval(-Double(retentionDays) * 86_400))
    }
}
