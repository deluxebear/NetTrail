import Foundation
import os
import TraceCore

/// XPC endpoint the app polls for event batches. Accepts only same-team clients.
final class EventServer: NSObject, NSXPCListenerDelegate, TraceFilterXPC {
    private let ring: EventRing
    private let listener: NSXPCListener
    private let log = Logger(subsystem: "com.xiongyanlin.trace.filter", category: "xpc")

    init?(ring: EventRing) {
        guard let info = Bundle.main.object(forInfoDictionaryKey: "NetworkExtension") as? [String: Any],
              let service = info["NEMachServiceName"] as? String,
              let teamID = Bundle.main.object(forInfoDictionaryKey: "TraceTeamID") as? String else { return nil }
        self.ring = ring
        listener = NSXPCListener(machServiceName: service)
        super.init()
        listener.setConnectionCodeSigningRequirement(TraceXPC.requirement(teamID: teamID))
        listener.delegate = self
    }

    func start() { listener.resume() }
    func stop() { listener.invalidate() }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: TraceFilterXPC.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func fetchEvents(maxCount: Int, reply: @escaping @Sendable (Data) -> Void) {
        let batch = ring.drain(max: maxCount)
        do {
            reply(try batch.encoded())
        } catch {
            log.error("encode failed: \(error.localizedDescription, privacy: .public)")
            reply(Data())
        }
    }
}
