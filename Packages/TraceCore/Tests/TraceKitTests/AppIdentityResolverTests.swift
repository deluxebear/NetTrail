import Foundation
import Testing
import TraceCore
@testable import TraceKit

private func makeFakeApp(named name: String, bundleID: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let app = root.appendingPathComponent("\(name).app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundlePackageType": "APPL"]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return app
}

@Suite struct AppIdentityResolverTests {
    @Test func findsOutermostAppBundle() {
        #expect(AppIdentityResolver.outermostAppBundle(containing:
            "/Applications/Slack.app/Contents/Frameworks/Slack Helper.app/Contents/MacOS/Slack Helper") == "/Applications/Slack.app")
        #expect(AppIdentityResolver.outermostAppBundle(containing: "/Applications/Safari.app") == "/Applications/Safari.app")
        #expect(AppIdentityResolver.outermostAppBundle(containing: "/usr/bin/curl") == nil)
    }

    @Test func helperIsGroupedUnderOutermostApp() throws {
        let app = try makeFakeApp(named: "Foo", bundleID: "com.example.foo")
        let helper = app.path + "/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper"
        let resolved = AppIdentityResolver().resolve(AppIdentity(
            signingID: "com.example.foo.helper", teamID: "T1", bundleID: "com.example.foo.helper",
            executablePath: helper, pid: 7))
        #expect(resolved == ResolvedApp(key: "com.example.foo", displayName: "Foo", bundleID: "com.example.foo",
                                        path: app.path, teamID: "T1"))
    }

    @Test func commandLineToolUsesSigningID() {
        let resolved = AppIdentityResolver().resolve(AppIdentity(
            signingID: "com.apple.curl", teamID: nil, bundleID: nil, executablePath: "/usr/bin/curl", pid: 1))
        #expect(resolved.key == "com.apple.curl")
        #expect(resolved.displayName == "curl")
        #expect(resolved.path == "/usr/bin/curl")
    }

    @Test func unsignedToolUsesPath() {
        let resolved = AppIdentityResolver().resolve(AppIdentity(
            signingID: nil, teamID: nil, bundleID: nil, executablePath: "/opt/tool/bin/thing", pid: 1))
        #expect(resolved.key == "/opt/tool/bin/thing")
        #expect(resolved.displayName == "thing")
    }
}
