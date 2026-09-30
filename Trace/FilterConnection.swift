import Foundation
import TraceCore

enum FilterConnectionError: Error {
    case noProxy
}

/// Resumes a continuation at most once (XPC may call both the reply and the error handler).
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire() -> Bool { lock.withLock { defer { fired = true }; return !fired } }
}

/// XPC client for the filter extension. Reconnects lazily after invalidation.
@MainActor
final class FilterConnection {
    private let machServiceName: String
    private let requirement: String
    private var connection: NSXPCConnection?

    init(machServiceName: String, teamID: String) {
        self.machServiceName = machServiceName
        requirement = TraceXPC.requirement(teamID: teamID)
    }

    func fetch(maxCount: Int) async throws -> EventBatch {
        let connection = currentConnection()
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                if once.fire() { continuation.resume(throwing: error) }
            } as? TraceFilterXPC
            guard let proxy else {
                if once.fire() { continuation.resume(throwing: FilterConnectionError.noProxy) }
                return
            }
            proxy.fetchEvents(maxCount: maxCount) { data in
                if once.fire() { continuation.resume(returning: data) }
            }
        }
        return try EventBatch.decode(data)
    }

    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: TraceFilterXPC.self)
        connection.setCodeSigningRequirement(requirement)
        let reset: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.invalidationHandler = reset
        connection.interruptionHandler = reset
        connection.resume()
        self.connection = connection
        return connection
    }
}
