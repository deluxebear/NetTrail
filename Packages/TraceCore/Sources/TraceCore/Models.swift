import Foundation

public enum TransportProtocol: String, Codable, Sendable, Equatable {
    case tcp, udp
}

public enum HostSource: String, Codable, Sendable, Equatable, CaseIterable {
    case system, sni, httpHost, dnsCache, none
}

public struct AppIdentity: Codable, Hashable, Sendable {
    public let signingID: String?
    public let teamID: String?
    public let bundleID: String?
    /// Code path: an .app/.systemextension bundle path or an executable path.
    public let executablePath: String
    public let pid: Int32

    public init(signingID: String?, teamID: String?, bundleID: String?, executablePath: String, pid: Int32) {
        self.signingID = signingID
        self.teamID = teamID
        self.bundleID = bundleID
        self.executablePath = executablePath
        self.pid = pid
    }

    public static let unknown = AppIdentity(signingID: nil, teamID: nil, bundleID: nil,
                                            executablePath: "unknown", pid: 0)
}

public struct Endpoint: Codable, Hashable, Sendable {
    public let ip: String
    public let port: UInt16
    public let proto: TransportProtocol

    public init(ip: String, port: UInt16, proto: TransportProtocol) {
        self.ip = ip
        self.port = port
        self.proto = proto
    }
}

/// Who started a process: what the code identity alone cannot tell (e.g. which app ran `curl`).
public struct ProcessOrigin: Codable, Hashable, Sendable {
    /// Executable path of the process macOS holds responsible (e.g. the app that spawned a helper tool),
    /// or nil when the process is responsible for itself.
    public let responsiblePath: String?
    /// Executable names of the parent chain, nearest first, ending before launchd.
    public let ancestors: [String]
    /// Script or module an interpreter (node, python, …) is running; inline code is never captured.
    public let script: String?

    public init(responsiblePath: String?, ancestors: [String], script: String?) {
        self.responsiblePath = responsiblePath
        self.ancestors = ancestors
        self.script = script
    }
}

public struct FlowOpened: Codable, Equatable, Sendable {
    public let flowID: UUID
    public let time: Date
    public let app: AppIdentity
    public let origin: ProcessOrigin?
    public let remote: Endpoint
    public let host: String?
    public let hostSource: HostSource

    public init(flowID: UUID, time: Date, app: AppIdentity, origin: ProcessOrigin? = nil,
                remote: Endpoint, host: String?, hostSource: HostSource) {
        self.flowID = flowID
        self.time = time
        self.app = app
        self.origin = origin
        self.remote = remote
        self.host = host
        self.hostSource = hostSource
    }
}

/// Bytes a still-open flow transferred since its previous report.
public struct FlowProgress: Codable, Equatable, Sendable {
    public let flowID: UUID
    public let time: Date
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(flowID: UUID, time: Date, bytesIn: UInt64, bytesOut: UInt64) {
        self.flowID = flowID
        self.time = time
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// A flow ended; the byte counts are what was not already sent in `FlowProgress` events.
public struct FlowClosed: Codable, Equatable, Sendable {
    public let flowID: UUID
    public let time: Date
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(flowID: UUID, time: Date, bytesIn: UInt64, bytesOut: UInt64) {
        self.flowID = flowID
        self.time = time
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

public enum FlowEvent: Codable, Equatable, Sendable {
    case opened(FlowOpened)
    case progress(FlowProgress)
    case closed(FlowClosed)
}

public struct EventBatch: Codable, Equatable, Sendable {
    public let events: [FlowEvent]
    public let droppedSinceLastBatch: UInt64

    public init(events: [FlowEvent], droppedSinceLastBatch: UInt64) {
        self.events = events
        self.droppedSinceLastBatch = droppedSinceLastBatch
    }

    public func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> EventBatch {
        try PropertyListDecoder().decode(EventBatch.self, from: data)
    }
}
