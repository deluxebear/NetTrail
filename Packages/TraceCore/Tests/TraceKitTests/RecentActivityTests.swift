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

    @Test func ratesCoverOnlyTheRateWindow() {
        let recent = RecentActivity(window: 300, rateWindow: 10)
        let a = app("com.a")
        recent.record(app: a, domain: "d.com", time: t0)
        recent.recordTraffic(app: a, domain: "d.com", time: t0.addingTimeInterval(1), bytesIn: 9_000, bytesOut: 900)
        recent.recordTraffic(app: a, domain: "d.com", time: t0.addingTimeInterval(15), bytesIn: 1_000, bytesOut: 100)
        let snapshot = recent.snapshot(now: t0.addingTimeInterval(20))
        #expect(snapshot.first?.rateIn == 100 && snapshot.first?.rateOut == 10)
        #expect(recent.snapshot(now: t0.addingTimeInterval(60)).first?.rateIn == 0)
    }

    @Test func trafficKeepsAppRecent() {
        let recent = RecentActivity(window: 300)
        let a = app("com.a")
        recent.record(app: a, domain: "stream.com", time: t0)
        recent.recordTraffic(app: a, domain: "stream.com", time: t0.addingTimeInterval(600), bytesIn: 1, bytesOut: 0)
        #expect(recent.snapshot(now: t0.addingTimeInterval(610)).map(\.key) == ["com.a"])
    }
}
