import Foundation
import SQLite3

/// Clock's current Core Data store is an implementation detail, not a public API.
/// Open read-only, query timer fields only, and fail closed if its schema changes.
/// No entitlements, private framework calls, archive object instantiation, or writes.
enum NativeTimerProbe {
    static var storeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Group Containers/group.com.apple.mobiletimerd/local.sqlite"
        )
    }

    static func scan(url: URL = storeURL, now: Date = Date()) -> NativeTimerActivity? {
        let timers = scanAll(url: url, now: now)
        // Running timers take precedence; among them show the soonest expiry.
        return timers.min {
            if $0.isPaused != $1.isPaused { return !$0.isPaused }
            return $0.remaining(at: now) < $1.remaining(at: now)
        }
    }

    static func scanAll(url: URL = storeURL, now: Date = Date()) -> [NativeTimerActivity] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 50)
        // States verified against native Clock: 1 idle, 2 paused, 3 running.
        let query = "SELECT hex(ZMTID), ZTITLE, ZDURATION, ZSTATE, ZFIRETIME FROM ZMTCDTIMER WHERE ZSTATE IN (2,3) ORDER BY ZLASTMODIFIEDDATE DESC LIMIT 64"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var timers: [NativeTimerActivity] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idBytes = sqlite3_column_text(statement, 0),
                  let bytes = sqlite3_column_blob(statement, 4) else { continue }
            let byteCount = Int(sqlite3_column_bytes(statement, 4))
            guard byteCount > 0, byteCount <= 65_536 else { continue }
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            guard let timer = decode(
                id: String(cString: idBytes), title: title,
                duration: sqlite3_column_double(statement, 2),
                state: Int(sqlite3_column_int(statement, 3)),
                fireTime: Data(bytes: bytes, count: byteCount)
            ), timer.remaining(at: now) > 0 else { continue }
            timers.append(timer)
        }
        return timers
    }

    static func decode(id: String, title: String, duration: TimeInterval, state: Int, fireTime: Data) -> NativeTimerActivity? {
        guard !id.isEmpty, duration.isFinite, duration > 0,
              fireTime.count <= 65_536,
              let plist = try? PropertyListSerialization.propertyList(from: fireTime, format: nil) as? [String: Any],
              plist["$archiver"] as? String == "NSKeyedArchiver",
              let objects = plist["$objects"] as? [Any], (2...16).contains(objects.count),
              let root = objects[1] as? [String: Any] else { return nil }
        let cleanTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let displayTitle = cleanTitle.isEmpty ? "Timer" : cleanTitle
        switch state {
        case 2:
            guard let remaining = root["MTTimerTimeInterval"] as? Double,
                  remaining.isFinite, remaining > 0, remaining <= duration else { return nil }
            return NativeTimerActivity(id: id, title: displayTitle, duration: duration, endDate: nil, pausedRemaining: remaining)
        case 3:
            guard root["MTTimerTimeDate"] != nil else { return nil }
            // A fire-date archive contains exactly one NSDate. Parse primitive data
            // rather than unarchiving private MTTimerDate / NSObject subclasses.
            let dates = objects.compactMap { ($0 as? [String: Any])?["NS.time"] as? Double }
            guard dates.count == 1, let seconds = dates.first, seconds.isFinite,
                  abs(seconds) < 100_000_000_000 else { return nil }
            return NativeTimerActivity(id: id, title: displayTitle, duration: duration,
                                       endDate: Date(timeIntervalSinceReferenceDate: seconds), pausedRemaining: nil)
        default:
            return nil
        }
    }
}
