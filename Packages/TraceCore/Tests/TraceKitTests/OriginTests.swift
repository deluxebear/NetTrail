import Foundation
import Testing
import TraceCore
@testable import TraceKit

private let ghostty = "/Applications/Ghostty.app/Contents/MacOS/ghostty"

@Suite struct OriginTests {
    let t0 = hourAligned

    private func open(_ key: String, _ domain: String, at offset: TimeInterval, origin: OriginInfo?) -> StoreOp {
        .open(app: app(key), domain: domain, resolved: true, source: .sni, time: t0.addingTimeInterval(offset), origin: origin)
    }

    @Test func originsGroupByViaAndScriptAcrossDomains() throws {
        let store = try Store.inMemory()
        let viaGhostty = OriginInfo(via: "Ghostty", viaPath: "/Applications/Ghostty.app", script: "", chain: "zsh ← ghostty")
        try store.apply([
            open("curl", "a.com", at: 0, origin: viaGhostty),
            open("curl", "b.com", at: 10, origin: OriginInfo(via: "Ghostty", viaPath: "/Applications/Ghostty.app",
                                                             script: "", chain: "bash ← zsh ← ghostty")),
            open("curl", "a.com", at: 5, origin: OriginInfo(via: "Raycast", viaPath: nil, script: "", chain: "Raycast")),
            open("curl", "a.com", at: 6, origin: nil),
        ])
        let all = try store.origins(appID: nil, domain: nil, range: .all, now: t0)
        #expect(all.map(\.via) == ["Ghostty", "Raycast"])
        #expect(all[0].connCount == 2 && all[0].chain == "bash ← zsh ← ghostty" && all[0].appName == "curl")
        let forDomain = try store.origins(appID: nil, domain: "b.com", range: .all, now: t0)
        #expect(forDomain.map(\.connCount) == [1])
    }

    @Test func originsRespectAppAndRange() throws {
        let store = try Store.inMemory()
        let origin = OriginInfo(via: "", viaPath: nil, script: "/srv/app.js", chain: "launchd-child")
        try store.apply([
            open("node", "a.com", at: 0, origin: origin),
            open("other", "a.com", at: 0, origin: origin),
        ])
        let nodeID = try #require(try store.apps(range: .all, now: t0).first(where: { $0.key == "node" })?.id)
        #expect(try store.origins(appID: nodeID, domain: nil, range: .all, now: t0).map(\.script) == ["/srv/app.js"])
        let later = t0.addingTimeInterval(2 * 86_400)
        #expect(try store.origins(appID: nil, domain: nil, range: .today, now: later).isEmpty)
        try store.deleteAll()
        #expect(try store.origins(appID: nil, domain: nil, range: .all, now: t0).isEmpty)
    }

    @Test func aggregatorNamesResponsibleAppOnlyWhenDifferent() throws {
        let store = try Store.inMemory()
        let aggregator = Aggregator(store: store) { identity in
            let path = AppIdentityResolver.outermostAppBundle(containing: identity.executablePath) ?? identity.executablePath
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return ResolvedApp(key: path, displayName: name, bundleID: nil, path: path, teamID: nil)
        }
        func flow(_ exe: String, responsible: String?) -> FlowEvent {
            .opened(FlowOpened(flowID: UUID(), time: t0,
                               app: AppIdentity(signingID: nil, teamID: nil, bundleID: nil, executablePath: exe, pid: 1),
                               origin: ProcessOrigin(responsiblePath: responsible, ancestors: ["zsh", "ghostty"], script: nil),
                               remote: Endpoint(ip: "1.2.3.4", port: 443, proto: .tcp), host: "x.com", hostSource: .sni))
        }
        try aggregator.ingest(EventBatch(events: [
            flow("/usr/bin/curl", responsible: ghostty),
            flow("/Applications/Ghostty.app/Contents/MacOS/helper", responsible: ghostty),
            flow("/Applications/Chrome.app/Contents/MacOS/Chrome",
                 responsible: "/private/var/folders/x/code_sign_clone/c.abc/Chrome.app.bundle/Contents/MacOS/Chrome"),
        ], droppedSinceLastBatch: 0), now: t0)
        let origins = try store.origins(appID: nil, domain: nil, range: .all, now: t0)
        let byApp = Dictionary(uniqueKeysWithValues: origins.map { ($0.appName, $0) })
        #expect(byApp["curl"]?.via == "Ghostty" && byApp["curl"]?.viaPath == "/Applications/Ghostty.app")
        #expect(byApp["curl"]?.chain == "zsh ← ghostty")
        #expect(byApp["Ghostty"]?.via == "")
        #expect(byApp["Chrome"]?.via == "")
    }
}
