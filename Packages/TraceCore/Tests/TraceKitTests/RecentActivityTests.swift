import Foundation
import Testing
@testable import TraceKit

@Suite struct RecentActivityTests {
    let t0 = hourAligned

    @Test func ordersAppsAndDomainsByRecency() {
        let recent = RecentActivity(window: 300)
        recent.record(app: app("com.a"), domain: "a1.com", time: t0)
        recent.record(app: app("com.b"), domain: "b1.com", time: t0.addingTimeInterval(10))
        recent.record(app: app("com.a"), domain: "a2.com", time: t0.addingTimeInterval(20))
        recent.record(app: app("com.a"), domain: "a1.com", time: t0.addingTimeInterval(30))
        let snapshot = recent.snapshot(now: t0.addingTimeInterval(31))
        #expect(snapshot.map(\.key) == ["com.a", "com.b"])
        #expect(snapshot[0].domains == ["a1.com", "a2.com"])
    }

    @Test func dropsActivityOutsideWindow() {
        let recent = RecentActivity(window: 300)
        recent.record(app: app("com.a"), domain: "old.com", time: t0)
        recent.record(app: app("com.b"), domain: "new.com", time: t0.addingTimeInterval(200))
        let snapshot = recent.snapshot(now: t0.addingTimeInterval(400))
        #expect(snapshot.map(\.key) == ["com.b"])
    }

    @Test func limitsNumberOfApps() {
        let recent = RecentActivity()
        for i in 0..<12 { recent.record(app: app("com.\(i)"), domain: "d.com", time: t0.addingTimeInterval(Double(i))) }
        #expect(recent.snapshot(now: t0.addingTimeInterval(20), limit: 8).count == 8)
    }
}
