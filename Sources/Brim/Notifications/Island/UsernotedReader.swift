// UsernotedReader.swift
// Brim
//
// Optional fallback: read delivered notifications from the usernoted SQLite database.
// Needs Full Disk Access. The database is copied (with its WAL) to a temp folder and opened
// read-only, so the live file is never touched or locked.

import Foundation
import SQLite3

enum UsernotedPlist {
  /// Parses a `record.data` blob: a binary plist with `req` = {titl, subt, body, ...}, `app`, `date`.
  static func parse(_ data: Data, fallbackBundleID: String? = nil) -> NotificationContent? {
    guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
      let req = root["req"] as? [String: Any]
    else { return nil }
    let bundle = (root["app"] as? String) ?? fallbackBundleID
    let content = NotificationContent(
      bundleID: bundle,
      appName: bundle.map(appDisplayName) ?? "Notification",
      title: (req["titl"] as? String) ?? "",
      subtitle: (req["subt"] as? String) ?? "",
      body: (req["body"] as? String) ?? "",
      date: referenceDate(root["date"]))
    return content.isEmpty ? nil : content
  }

  private static func referenceDate(_ value: Any?) -> Date {
    if let date = value as? Date { return date }
    if let seconds = value as? Double { return Date(timeIntervalSinceReferenceDate: seconds) }
    return Date()
  }

  /// Display name resolved by the caller's `NotificationAppResolver`; here we only fall back to the id.
  static var appDisplayName: (String) -> String = { $0 }
}

final class UsernotedReader {
  struct Row { let recID: Int64; let bundleID: String?; let data: Data }

  /// macOS 15+ keeps the store in usernoted's group container; older releases used DARWIN_USER_DIR.
  static var databaseURL: URL? {
    candidateURLs.first { FileManager.default.fileExists(atPath: $0.path) }
  }

  static var candidateURLs: [URL] {
    let groupContainer = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 else { return [groupContainer] }
    let legacy = URL(fileURLWithPath: String(cString: buffer))
      .appendingPathComponent("com.apple.notificationcenter/db2/db")
    return [groupContainer, legacy]
  }

  /// Full Disk Access check: the file must be readable, not merely present.
  static var isReadable: Bool {
    guard let url = databaseURL, let handle = try? FileHandle(forReadingFrom: url) else { return false }
    try? handle.close()
    return true
  }

  private(set) var lastRecID: Int64?

  /// Rows added since the previous call. The first call only records the high-water mark.
  func newContent() -> [NotificationContent] {
    guard let rows = try? readRows(after: lastRecID) else { return [] }
    let isFirst = lastRecID == nil
    if let max = rows.map(\.recID).max() { lastRecID = max } else if isFirst { lastRecID = 0 }
    if isFirst { return [] }
    return rows.compactMap { UsernotedPlist.parse($0.data, fallbackBundleID: $0.bundleID) }
  }

  private func readRows(after: Int64?) throws -> [Row] {
    guard let source = Self.databaseURL else { return [] }
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("qs-usernoted-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let copy = temp.appendingPathComponent("db")
    for suffix in ["", "-wal", "-shm"] {
      let from = URL(fileURLWithPath: source.path + suffix)
      if FileManager.default.fileExists(atPath: from.path) {
        try FileManager.default.copyItem(at: from, to: URL(fileURLWithPath: copy.path + suffix))
      }
    }
    return try Self.query(database: copy, after: after)
  }

  static func query(database: URL, after: Int64?) throws -> [Row] {
    var db: OpaquePointer?
    guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(db)
      throw NSError(domain: "Usernoted", code: 1)
    }
    defer { sqlite3_close(db) }
    let sql = """
      SELECT r.rec_id, a.identifier, r.data FROM record r LEFT JOIN app a ON a.app_id = r.app_id \
      WHERE r.rec_id > ? ORDER BY r.rec_id LIMIT 50
      """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw NSError(domain: "Usernoted", code: 2) }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_int64(statement, 1, after ?? 0)
    var rows: [Row] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let id = sqlite3_column_int64(statement, 0)
      let bundle = sqlite3_column_text(statement, 1).map { String(cString: $0) }
      let length = Int(sqlite3_column_bytes(statement, 2))
      guard length > 0, let bytes = sqlite3_column_blob(statement, 2) else { continue }
      rows.append(Row(recID: id, bundleID: bundle, data: Data(bytes: bytes, count: length)))
    }
    return rows
  }
}
