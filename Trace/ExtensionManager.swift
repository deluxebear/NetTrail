import Foundation
import NetworkExtension
import SystemExtensions

/// Installs the filter system extension and enables its NEFilterManager configuration.
@MainActor
final class ExtensionManager: NSObject, ObservableObject {
    enum ExtensionState: Equatable {
        case unknown, notInstalled, needsApproval, activated
        case failed(String)
    }

    private enum RequestKind { case properties, activation, deactivation }

    @Published private(set) var extensionState: ExtensionState = .unknown
    @Published private(set) var filterEnabled = false
    @Published private(set) var lastError: String?

    let extensionID = (Bundle.main.bundleIdentifier ?? "com.xiongyanlin.trace") + ".filter"
    private var requestKinds: [ObjectIdentifier: RequestKind] = [:]
    private var configObserver: NSObjectProtocol?

    var isReady: Bool { extensionState == .activated && filterEnabled }

    override init() {
        super.init()
        configObserver = NotificationCenter.default.addObserver(
            forName: .NEFilterConfigurationDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.loadFilterState() }
        }
    }

    func refresh() async {
        submit(.propertiesRequest(forExtensionWithIdentifier: extensionID, queue: .main), kind: .properties)
        await loadFilterState()
    }

    func install() {
        lastError = nil
        submit(.activationRequest(forExtensionWithIdentifier: extensionID, queue: .main), kind: .activation)
    }

    func enableFilter() async {
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
            if manager.providerConfiguration == nil {
                let configuration = NEFilterProviderConfiguration()
                configuration.filterSockets = true
                configuration.filterPackets = false
                manager.providerConfiguration = configuration
            }
            manager.localizedDescription = "Trace"
            manager.isEnabled = true
            try await manager.saveToPreferences()
            lastError = nil
        } catch {
            lastError = "启用内容过滤失败：\(error.localizedDescription)"
        }
        await loadFilterState()
    }

    func uninstall() async {
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
            try await manager.removeFromPreferences()
        } catch {
            lastError = "移除过滤配置失败：\(error.localizedDescription)"
        }
        await loadFilterState()
        submit(.deactivationRequest(forExtensionWithIdentifier: extensionID, queue: .main), kind: .deactivation)
    }

    private func loadFilterState() async {
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
            filterEnabled = manager.isEnabled && manager.providerConfiguration != nil
        } catch {
            filterEnabled = false
        }
    }

    private func submit(_ request: OSSystemExtensionRequest, kind: RequestKind) {
        requestKinds[ObjectIdentifier(request)] = kind
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
}

extension ExtensionManager: OSSystemExtensionRequestDelegate {
    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        MainActor.assumeIsolated { extensionState = .needsApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishWithResult result: OSSystemExtensionRequest.Result) {
        MainActor.assumeIsolated {
            let kind = requestKinds.removeValue(forKey: ObjectIdentifier(request))
            switch kind {
            case .activation:
                extensionState = .activated
                Task { await enableFilter() }
            case .deactivation:
                extensionState = .notInstalled
            case .properties, nil:
                break
            }
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            let kind = requestKinds.removeValue(forKey: ObjectIdentifier(request))
            if kind == .properties {
                if extensionState == .unknown { extensionState = .notInstalled }
            } else {
                extensionState = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             foundProperties properties: [OSSystemExtensionProperties]) {
        MainActor.assumeIsolated {
            requestKinds.removeValue(forKey: ObjectIdentifier(request))
            if properties.contains(where: { $0.isEnabled && !$0.isUninstalling }) {
                extensionState = .activated
            } else if properties.contains(where: { $0.isAwaitingUserApproval }) {
                extensionState = .needsApproval
            } else {
                extensionState = .notInstalled
            }
        }
    }
}
