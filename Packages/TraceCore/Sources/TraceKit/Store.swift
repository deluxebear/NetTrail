import Foundation
import GRDB
import TraceCore

public final class Store: Sendable {
    private let queue: any DatabaseWriter

    /// WAL-mode pool, so reads are not blocked by an in-progress write.
    public convenience init(path: String) throws {
        try self.init(queue: DatabasePool(path: path))
    }

    private init(queue: any DatabaseWriter) throws {
        self.queue = queue
        try Self.migrator.migrate(queue)
    }

    public static func inMemory() throws -> Store {
        try Store(queue: DatabaseQueue())
    }

    /// Opens the database; if it cannot be opened, moves it aside and starts empty.
    public static func openRecovering(at url: URL, now: Date = Date()) throws -> (store: Store, backupURL: URL?) {
        do {
            return (try Store(path: url.path), nil)
        } catch {
            let backup = url.appendingPathExtension("corrupt-\(Int(now.timeIntervalSince1970))")
            let fm = FileManager.default
            try fm.moveItem(at: url, to: backup)
            for suffix in ["-wal", "-shm", "-journal"] {
                try? fm.removeItem(atPath: url.path + suffix)
            }
            return (try Store(path: url.path), backup)
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE app (
                  id INTEGER PRIMARY KEY,
                  identity_key TEXT NOT NULL UNIQUE,
                  bundle_id TEXT, display_name TEXT, path TEXT, team_id TEXT,
                  first_seen REAL NOT NULL, last_seen REAL NOT NULL
                );
                CREATE TABLE app_domain (
                  app_id INTEGER NOT NULL REFERENCES app(id),
                  domain TEXT NOT NULL,
                  resolved INTEGER NOT NULL,
                  last_source TEXT NOT NULL,
                  first_seen REAL NOT NULL, last_seen REAL NOT NULL,
                  conn_count INTEGER NOT NULL DEFAULT 0,
                  bytes_in INTEGER NOT NULL DEFAULT 0, bytes_out INTEGER NOT NULL DEFAULT 0,
                  PRIMARY KEY (app_id, domain)
                );
                CREATE TABLE app_domain_hourly (
                  app_id INTEGER NOT NULL, domain TEXT NOT NULL,
                  hour INTEGER NOT NULL,
                  conn_count INTEGER NOT NULL DEFAULT 0,
                  bytes_in INTEGER NOT NULL DEFAULT 0, bytes_out INTEGER NOT NULL DEFAULT 0,
                  PRIMARY KEY (app_id, domain, hour)
                );
                CREATE INDEX app_domain_hourly_hour ON app_domain_hourly(hour);
                CREATE INDEX app_domain_hourly_domain ON app_domain_hourly(domain, hour);
                """)
        }
        return migrator
    }

    static func hour(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 / 3600).rounded(.down))
    }

    // MARK: Writes

    public func apply(_ ops: [StoreOp]) throws {
        guard !ops.isEmpty else { return }
        try queue.write { db in
            var ids: [String: Int64] = [:]
            func appID(_ key: String) throws -> Int64? {
                if let cached = ids[key] { return cached }
                let found = try Int64.fetchOne(db, sql: "SELECT id FROM app WHERE identity_key = ?", arguments: [key])
                ids[key] = found
                return found
            }
            for op in ops {
                switch op {
                case let .open(app, domain, resolved, source, time):
                    let t = time.timeIntervalSince1970
                    try db.execute(sql: """
                        INSERT INTO app (identity_key, bundle_id, display_name, path, team_id, first_seen, last_seen)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(identity_key) DO UPDATE SET
                          bundle_id = excluded.bundle_id, display_name = excluded.display_name,
                          path = excluded.path, team_id = excluded.team_id,
                          last_seen = MAX(last_seen, excluded.last_seen)
                        """, arguments: [app.key, app.bundleID, app.displayName, app.path, app.teamID, t, t])
                    ids[app.key] = nil
                    guard let id = try appID(app.key) else { continue }
                    try db.execute(sql: """
                        INSERT INTO app_domain (app_id, domain, resolved, last_source, first_seen, last_seen, conn_count)
                        VALUES (?, ?, ?, ?, ?, ?, 1)
                        ON CONFLICT(app_id, domain) DO UPDATE SET
                          conn_count = conn_count + 1,
                          resolved = excluded.resolved, last_source = excluded.last_source,
                          last_seen = MAX(last_seen, excluded.last_seen)
                        """, arguments: [id, domain, resolved, source.rawValue, t, t])
                    try db.execute(sql: """
                        INSERT INTO app_domain_hourly (app_id, domain, hour, conn_count) VALUES (?, ?, ?, 1)
                        ON CONFLICT(app_id, domain, hour) DO UPDATE SET conn_count = conn_count + 1
                        """, arguments: [id, domain, Self.hour(time)])
                case let .close(appKey, domain, time, bytesIn, bytesOut):
                    guard let id = try appID(appKey) else { continue }
                    let t = time.timeIntervalSince1970
                    let inBytes = Int64(clamping: bytesIn)
                    let outBytes = Int64(clamping: bytesOut)
                    try db.execute(sql: """
                        UPDATE app_domain SET bytes_in = bytes_in + ?, bytes_out = bytes_out + ?,
                          last_seen = MAX(last_seen, ?)
                        WHERE app_id = ? AND domain = ?
                        """, arguments: [inBytes, outBytes, t, id, domain])
                    try db.execute(sql: """
                        INSERT INTO app_domain_hourly (app_id, domain, hour, bytes_in, bytes_out) VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(app_id, domain, hour) DO UPDATE SET
                          bytes_in = bytes_in + excluded.bytes_in, bytes_out = bytes_out + excluded.bytes_out
                        """, arguments: [id, domain, Self.hour(time), inBytes, outBytes])
                    try db.execute(sql: "UPDATE app SET last_seen = MAX(last_seen, ?) WHERE id = ?", arguments: [t, id])
                }
            }
        }
    }

    public func purge(before date: Date) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM app_domain_hourly WHERE hour < ?", arguments: [Self.hour(date)])
        }
    }

    public func deleteAll() throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM app_domain_hourly; DELETE FROM app_domain; DELETE FROM app;")
        }
    }

    // MARK: Reads

    /// `s` is the aggregated source (hourly buckets for a range, summary rows for `.all`); `d` is the summary row.
    private func source(for range: TimeRange, now: Date, calendar: Calendar) -> (from: String, conditions: [String], arguments: [(any DatabaseValueConvertible)?]) {
        if let start = range.startDate(now: now, calendar: calendar) {
            return ("app_domain_hourly s JOIN app_domain d ON d.app_id = s.app_id AND d.domain = s.domain",
                    ["s.hour >= ?"], [Self.hour(start)])
        }
        return ("app_domain s JOIN app_domain d ON d.app_id = s.app_id AND d.domain = s.domain", [], [])
    }

    private static func whereClause(_ conditions: [String]) -> String {
        conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
    }

    public func apps(range: TimeRange, domain: String? = nil, now: Date = Date(), calendar: Calendar = .current) throws -> [AppSummary] {
        var conditions: [String] = []
        var arguments: [(any DatabaseValueConvertible)?] = []
        let table: String
        if let start = range.startDate(now: now, calendar: calendar) {
            table = "app_domain_hourly"
            conditions.append("s.hour >= ?")
            arguments.append(Self.hour(start))
        } else {
            table = "app_domain"
        }
        if let domain {
            conditions.append("s.domain = ?")
            arguments.append(domain)
        }
        let sql = """
            SELECT a.id, a.identity_key, a.display_name, a.bundle_id, a.path, a.last_seen,
                   SUM(s.conn_count) AS conn, SUM(s.bytes_in) AS bin, SUM(s.bytes_out) AS bout,
                   COUNT(DISTINCT s.domain) AS dc
            FROM app a JOIN \(table) s ON s.app_id = a.id
            \(Self.whereClause(conditions))
            GROUP BY a.id ORDER BY a.last_seen DESC
            """
        let statementArguments = StatementArguments(arguments)
        return try queue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: statementArguments).map { row in
                let key: String = row["identity_key"]
                return AppSummary(
                    id: row["id"], key: key,
                    displayName: row["display_name"] ?? key,
                    bundleID: row["bundle_id"], path: row["path"],
                    lastSeen: Date(timeIntervalSince1970: row["last_seen"]),
                    connCount: row["conn"], bytesIn: row["bin"], bytesOut: row["bout"],
                    domainCount: row["dc"])
            }
        }
    }

    public func domains(appID: Int64?, range: TimeRange, now: Date = Date(), calendar: Calendar = .current) throws -> [DomainSummary] {
        var (from, conditions, arguments) = source(for: range, now: now, calendar: calendar)
        if let appID {
            conditions.append("s.app_id = ?")
            arguments.append(appID)
        }
        let sql = """
            SELECT s.domain AS domain, MAX(d.resolved) AS resolved, MAX(d.last_source) AS last_source,
                   MIN(d.first_seen) AS first_seen, MAX(d.last_seen) AS last_seen,
                   SUM(s.conn_count) AS conn, SUM(s.bytes_in) AS bin, SUM(s.bytes_out) AS bout
            FROM \(from)
            \(Self.whereClause(conditions))
            GROUP BY s.domain ORDER BY last_seen DESC
            """
        let statementArguments = StatementArguments(arguments)
        return try queue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: statementArguments).map { row in
                DomainSummary(
                    domain: row["domain"],
                    resolved: row["resolved"],
                    lastSource: HostSource(rawValue: row["last_source"]) ?? .none,
                    firstSeen: Date(timeIntervalSince1970: row["first_seen"]),
                    lastSeen: Date(timeIntervalSince1970: row["last_seen"]),
                    connCount: row["conn"], bytesIn: row["bin"], bytesOut: row["bout"])
            }
        }
    }

    public func hourly(appID: Int64?, domain: String, since: Date) throws -> [HourPoint] {
        var sql = """
            SELECT hour, SUM(conn_count) AS conn, SUM(bytes_in) AS bin, SUM(bytes_out) AS bout
            FROM app_domain_hourly WHERE domain = ? AND hour >= ?
            """
        var arguments: [(any DatabaseValueConvertible)?] = [domain, since == .distantPast ? Int64.min : Self.hour(since)]
        if let appID {
            sql += " AND app_id = ?"
            arguments.append(appID)
        }
        sql += " GROUP BY hour ORDER BY hour"
        let statementArguments = StatementArguments(arguments)
        return try queue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: statementArguments).map { row in
                let hour: Int64 = row["hour"]
                return HourPoint(hour: Date(timeIntervalSince1970: TimeInterval(hour) * 3600),
                                 connCount: row["conn"], bytesIn: row["bin"], bytesOut: row["bout"])
            }
        }
    }
}
