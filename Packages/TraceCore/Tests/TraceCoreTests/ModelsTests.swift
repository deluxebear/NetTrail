import Foundation
import Testing
@testable import TraceCore

@Test func eventBatchRoundTrips() throws {
    let app = AppIdentity(signingID: "com.apple.curl", teamID: nil, bundleID: nil,
                          executablePath: "/usr/bin/curl", pid: 42)
    let id = UUID()
    let batch = EventBatch(events: [
        .opened(FlowOpened(flowID: id, time: Date(timeIntervalSince1970: 1_700_000_000.25), app: app,
                           origin: ProcessOrigin(responsiblePath: "/Applications/Ghostty.app/Contents/MacOS/ghostty",
                                                 ancestors: ["zsh", "ghostty"], script: nil),
                           remote: Endpoint(ip: "93.184.216.34", port: 443, proto: .tcp),
                           host: "example.com", hostSource: .sni)),
        .closed(FlowClosed(flowID: id, time: Date(timeIntervalSince1970: 1_700_000_005), bytesIn: 10, bytesOut: 20)),
    ], droppedSinceLastBatch: 3)
    let decoded = try EventBatch.decode(batch.encoded())
    #expect(decoded == batch)
}

@Test func decodingGarbageThrows() {
    #expect(throws: (any Error).self) { try EventBatch.decode(Data([1, 2, 3])) }
}

@Test func flowWithoutOriginRoundTrips() throws {
    let app = AppIdentity(signingID: nil, teamID: nil, bundleID: nil, executablePath: "/usr/bin/curl", pid: 1)
    let batch = EventBatch(events: [
        .opened(FlowOpened(flowID: UUID(), time: Date(timeIntervalSince1970: 1), app: app,
                           remote: Endpoint(ip: "1.1.1.1", port: 80, proto: .tcp), host: nil, hostSource: .none)),
    ], droppedSinceLastBatch: 0)
    #expect(try EventBatch.decode(batch.encoded()) == batch)
}
