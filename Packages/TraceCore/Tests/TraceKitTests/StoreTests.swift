import Foundation
import Testing
import TraceCore
@testable import TraceKit

let hourAligned = Date(timeIntervalSince1970: 472_222 * 3600)   // 2023-11-14 22:00 UTC

func app(_ key: String, name: String? = nil, path: String = "/Applications/X.app") -> ResolvedApp {
    ResolvedApp(key: key, displayName: name ?? key, bundleID: key, path: path, teamID: nil)
}

@Suite struct StoreTests {
    let t0 = hourAligned

    @Test func openThenCloseAccumulates() throws {
        let store = try Store.inMemory()
        try store.apply([
            .open(app: app("com.a"), domain: "api.x.com", resolved: true, source: .sni, time: t0),
            .close(appKey: "com.a", domain: "api.x.com", time: t0.addingTimeInterval(10), bytesIn: 100, bytesOut: 50),
        ])
        let apps = try store.apps(range: .all, now: t0)
        #expect(apps.count == 1)
        #expect(apps[0].connCount == 1 && apps[0].bytesIn == 100 && apps[0].bytesOut == 50 && apps[0].domainCount == 1)
        let domains = try store.domains(appID: apps[0].id, range: .all, now: t0)
        #expect(domains.map(\.domain) == ["api.x.com"])
        #expect(domains[0].lastSource == .sni && domains[0].resolved)
        #expect(domains[0].firstSeen == t0 && domains[0].lastSeen == t0.addingTimeInterval(10))
    }

    @Test func connectionsAndBytesLandInTheirOwnHours() throws {
        let store = try Store.inMemory()
        try store.apply([
            .open(app: app("com.a"), domain: "d.com", resolved: true, source: .sni, time: t0.addingTimeInterval(3500)),
            .close(appKey: "com.a", domain: "d.com", time: t0.addingTimeInterval(3700), bytesIn: 7, bytesOut: 3),
        ])
        let points = try store.hourly(appID: nil, domain: "d.com", since: t0)
        #expect(points.count == 2)
        #expect(points[0].hour == t0 && points[0].connCount == 1 && points[0].bytesIn == 0)
        #expect(points[1].hour == t0.addingTimeInterval(3600) && points[1].connCount == 0 && points[1].bytesIn == 7)
    }

    @Test func rangeFiltersByHourBucket() throws {
        let store = try Store.inMemory()
        let later = t0.addingTimeInterval(10 * 86_400)
        try store.apply([
            .open(app: app("com.a"), domain: "old.com", resolved: true, source: .sni, time: t0),
            .open(app: app("com.a"), domain: "new.com", resolved: true, source: .sni, time: later),
        ])
        let now = later.addingTimeInterval(60)
        let week = try store.apps(range: .last7Days, now: now)
        #expect(week.first?.connCount == 1 && week.first?.domainCount == 1)
        let all = try store.apps(range: .all, now: now)
        #expect(all.first?.connCount == 2)
        #expect(try store.domains(appID: nil, range: .last7Days, now: now).map(\.domain) == ["new.com"])
    }

    @Test func todayStartsAtLocalMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-15 06:13 in Shanghai
        let start = TimeRange.today.startDate(now: now, calendar: calendar)!
        #expect(calendar.component(.hour, from: start) == 0)
        #expect(now.timeIntervalSince(start) < 86_400)
        #expect(TimeRange.all.startDate(now: now, calendar: calendar) == nil)
    }

    @Test func reopeningAppUpdatesNameAndKeepsOneRow() throws {
        let store = try Store.inMemory()
        try store.apply([.open(app: app("com.a", name: "Old", path: "/old/A.app"), domain: "d.com", resolved: true, source: .sni, time: t0)])
        try store.apply([.open(app: app("com.a", name: "New", path: "/new/A.app"), domain: "d.com", resolved: true, source: .sni, time: t0.addingTimeInterval(5))])
        let apps = try store.apps(range: .all, now: t0)
        #expect(apps.count == 1)
        #expect(apps[0].displayName == "New" && apps[0].path == "/new/A.app" && apps[0].connCount == 2)
    }

    @Test func hugeByteCountsAreClamped() throws {
        let store = try Store.inMemory()
        try store.apply([
            .open(app: app("com.a"), domain: "d.com", resolved: true, source: .sni, time: t0),
            .close(appKey: "com.a", domain: "d.com", time: t0, bytesIn: .max, bytesOut: .max),
        ])
        #expect(try store.apps(range: .all, now: t0).first?.bytesIn == Int64.max)
    }

    @Test func repeatedOpsInOneBatchAreMerged() throws {
        let store = try Store.inMemory()
        try store.apply([
            .open(app: app("com.a"), domain: "d.com", resolved: false, source: .dnsCache, time: t0.addingTimeInterval(20)),
            .open(app: app("com.a"), domain: "d.com", resolved: true, source: .sni, time: t0.addingTimeInterval(10)),
            .open(app: app("com.a", name: "Middle"), domain: "d.com", resolved: true, source: .httpHost, time: t0.addingTimeInterval(30)),
            .open(app: app("com.a"), domain: "d.com", resolved: true, source: .sni, time: t0.addingTimeInterval(3600)),
            .close(appKey: "com.a", domain: "d.com", time: t0.addingTimeInterval(40), bytesIn: 5, bytesOut: 1),
            .close(appKey: "com.a", domain: "d.com", time: t0.addingTimeInterval(50), bytesIn: 7, bytesOut: 2),
        ])
        let apps = try store.apps(range: .all, now: t0)
        #expect(apps.count == 1)
        #expect(apps[0].displayName == "com.a" && apps[0].connCount == 4 && apps[0].bytesIn == 12 && apps[0].bytesOut == 3)
        let domain = try #require(try store.domains(appID: nil, range: .all, now: t0).first)
        #expect(domain.lastSource == .sni && domain.resolved)
        #expect(domain.firstSeen == t0.addingTimeInterval(10) && domain.lastSeen == t0.addingTimeInterval(3600))
        let points = try store.hourly(appID: nil, domain: "d.com", since: t0)
        #expect(points.map(\.connCount) == [3, 1])
        #expect(points.map(\.bytesIn) == [12, 0])
    }

    @Test func mergedByteSumsSaturate() throws {
        let store = try Store.inMemory()
        try store.apply([
            .open(app: app("com.a"), domain: "d.com", resolved: true, source: .sni, time: t0),
            .close(appKey: "com.a", domain: "d.com", time: t0, bytesIn: .max, bytesOut: 1),
            .close(appKey: "com.a", domain: "d.com", time: t0, bytesIn: .max, bytesOut: 1),
        ])
        try store.apply([.close(appKey: "com.a", domain: "d.com", time: t0, bytesIn: 1, bytesOut: 1)])
        let summary = try #require(try store.apps(range: .all, now: t0).first)
        #expect(summary.bytesIn == Int64.max && summary.bytesOut == 3)
        let domain = try #require(try store.domains(appID: nil, range: .all, now: t0).first)
        #expect(domain.bytesIn == Int64.max)
    }

    @Test func closeForUnknownAppIsIgnored() throws {
        let store = try Store.inMemory()
        try store.apply([.close(appKey: "nobody", domain: "d.com", time: t0, bytesIn: 1, bytesOut: 1)])
        #expect(try store.apps(range: .all, now: t0).isEmpty)
    }

    @Test func domainQueriesAggregateAcrossApps() throws {
        let store = try Store.inMemory()
        try store.apply([
            .open(app: app("com.a"), domain: "shared.com", resolved: true, source: .sni, time: t0),
            .open(app: app("com.b"), domain: "shared.com", resolved: true, source: .system, time: t0.addingTimeInterval(1)),
            .open(app: app("com.b"), domain: "10.0.0.1", resolved: false, source: .none, time: t0.addingTimeInterval(2)),
        ])
        let all = try store.domains(appID: nil, range: .all, now: t0)
        #expect(all.first(where: { $0.domain == "shared.com" })?.connCount == 2)
        #expect(all.first(where: { $0.domain == "10.0.0.1" })?.resolved == false)
        let users = try store.apps(range: .all, domain: "shared.com", now: t0)
        #expect(Set(users.map(\.key)) == ["com.a", "com.b"])
        #expect(try store.hourly(appID: nil, domain: "shared.com", since: t0).first?.connCount == 2)
        let aID = try #require(users.first(where: { $0.key == "com.a" })?.id)
        #expect(try store.hourly(appID: aID, domain: "shared.com", since: t0).first?.connCount == 1)
    }

    @Test func purgeRemovesOldHoursButKeepsSummary() throws {
        let store = try Store.inMemory()
        try store.apply([.open(app: app("com.a"), domain: "d.com", resolved: true, source: .sni, time: t0)])
        try store.purge(before: t0.addingTimeInterval(3600))
        #expect(try store.hourly(appID: nil, domain: "d.com", since: .distantPast).isEmpty)
        #expect(try store.apps(range: .all, now: t0).first?.connCount == 1)
    }

    @Test func deleteAllEmptiesEverything() throws {
        let store = try Store.inMemory()
        try store.apply([.open(app: app("com.a"), domain: "d.com", resolved: true, source: .sni, time: t0)])
        try store.deleteAll()
        #expect(try store.apps(range: .all, now: t0).isEmpty)
        #expect(try store.domains(appID: nil, range: .all, now: t0).isEmpty)
    }

    @Test func openRecoveringPersistsHealthyDatabase() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("trace.sqlite")
        do {
            let (store, backup) = try Store.openRecovering(at: url)
            #expect(backup == nil)
            try store.apply([.open(app: app("com.a"), domain: "d.com", resolved: true, source: .sni, time: t0)])
        }
        let (reopened, backup) = try Store.openRecovering(at: url)
        #expect(backup == nil)
        #expect(try reopened.apps(range: .all, now: t0).count == 1)
    }

    @Test func openRecoveringBacksUpCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("trace.sqlite")
        try Data(repeating: 0x5A, count: 4096).write(to: url)
        let (store, backup) = try Store.openRecovering(at: url, now: t0)
        let backupURL = try #require(backup)
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        try store.apply([.open(app: app("com.a"), domain: "d.com", resolved: true, source: .sni, time: t0)])
        #expect(try store.apps(range: .all, now: t0).count == 1)
    }
}
