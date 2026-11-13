import Foundation
import SQLite3

/// Minimal read-only SQLite helper. Never writes to Copilot's databases.
enum SQLiteReader {
    static func rows(path: String, sql: String) -> [[String: String]] {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK else { NSLog("PajlotAssist: open failed \(rc) \(path)"); sqlite3_close(db); return [] }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { NSLog("PajlotAssist: prepare failed: \(String(cString: sqlite3_errmsg(db)))"); return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [[String: String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: String] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, i))
                if let c = sqlite3_column_text(stmt, i) { row[name] = String(cString: c) }
            }
            out.append(row)
        }
        return out
    }
}
