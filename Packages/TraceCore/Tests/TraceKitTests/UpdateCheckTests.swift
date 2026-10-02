import Foundation
import Testing
@testable import TraceKit

@Suite struct UpdateCheckTests {
    private func v(_ s: String) -> AppVersion { AppVersion(s)! }

    @Test func ordersNumericComponents() {
        #expect(v("0.1.0") < v("0.1.1"))
        #expect(v("0.9.0") < v("0.10.0"))
        #expect(!(v("1.0") < v("1.0.0")) && !(v("1.0.0") < v("1.0")))
        #expect(v("v1.2.0") == v("1.2.0"))
    }
    @Test func preReleaseSortsBeforeRelease() {
        #expect(v("0.1.0-rc.7") < v("0.1.0"))
        #expect(v("0.1.0-rc.7") < v("0.1.0-rc.10"))
        #expect(v("0.1.0") > v("0.1.0-rc.1"))
    }
    @Test func rejectsGarbage() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("1.x") == nil)
    }

    private func json(tag: String, draft: Bool = false, pre: Bool = false) -> Data {
        Data("""
        {"tag_name":"\(tag)","html_url":"https://github.com/deluxebear/NetTrail/releases/tag/\(tag)","draft":\(draft),"prerelease":\(pre)}
        """.utf8)
    }
    @Test func reportsNewerRelease() {
        let update = UpdateCheck.newerRelease(current: "0.1.0", json: json(tag: "v0.2.0"))
        #expect(update?.version == "0.2.0")
        #expect(update?.url.absoluteString == "https://github.com/deluxebear/NetTrail/releases/tag/v0.2.0")
    }
    @Test func upgradesPreReleaseToItsRelease() {
        #expect(UpdateCheck.newerRelease(current: "0.1.0-rc.7", json: json(tag: "v0.1.0")) != nil)
    }
    @Test func ignoresSameOlderDraftAndPrerelease() {
        #expect(UpdateCheck.newerRelease(current: "0.2.0", json: json(tag: "v0.2.0")) == nil)
        #expect(UpdateCheck.newerRelease(current: "0.3.0", json: json(tag: "v0.2.0")) == nil)
        #expect(UpdateCheck.newerRelease(current: "0.1.0", json: json(tag: "v0.2.0", draft: true)) == nil)
        #expect(UpdateCheck.newerRelease(current: "0.1.0", json: json(tag: "v0.2.0", pre: true)) == nil)
        #expect(UpdateCheck.newerRelease(current: "0.1.0", json: Data("{}".utf8)) == nil)
    }
}
