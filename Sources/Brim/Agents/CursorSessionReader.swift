import Foundation
import SQLite3

/// Reads Cursor's agent sessions from `globalStorage/state.vscdb` (read-only, never copied: it can be many GB).
/// `composerHeaders` holds one row per chat with `lastUpdatedAt`, line counts and `hasBlockingPendingActions`;
/// the newest tool call comes from the last `bubbleId:<composer>:*` row in `cursorDiskKV`.
enum CursorSessionParser {
  /// A header row's JSON, plus the newest bubble's JSON when one was read.
  static func session(header: [String: Any], bubble: [String: Any]?, workspaceName: String?, now: Date = .now)
    -> CodingAgentSession?
  {
    guard let composerID = header["composerId"] as? String,
      header["isArchived"] as? Bool != true, header["isDraft"] as? Bool != true,
      let updatedMS = (header["lastUpdatedAt"] as? NSNumber)?.doubleValue
    else { return nil }
    let updated = Date(timeIntervalSince1970: updatedMS / 1000)
    let tool = bubble?["toolFormerData"] as? [String: Any]
    let toolStatus = tool?["status"] as? String
    let toolRunning = toolStatus == "loading" || toolStatus == "running" || toolStatus == "pending"
    let step = tool.flatMap { describe(name: $0["name"] as? String, params: $0["params"] ?? $0["rawArgs"]) }
    let blocked = header["hasBlockingPendingActions"] as? Bool == true
    let generating = (header["status"] as? String) == "generating"
    let fresh = now.timeIntervalSince(updated) < 20
    let state: CodingAgentSession.State
    if blocked {
      state = .needsInput(step.map { "Approve: \($0)" } ?? "Needs your input")
    } else if let step, toolRunning {
      state = .running(step)
    } else if generating || fresh {
      state = .thinking
    } else {
      state = .waiting
    }
    let tokens = bubble?["tokenCount"] as? [String: Any]
    var session = CodingAgentSession(
      tool: .cursor, model: nil, state: state, steps: step.map { [$0] } ?? [],
      lastMessage: (header["subtitle"] as? String).flatMap { $0.isEmpty ? nil : $0 },
      outputTokens: tokens?["outputTokens"] as? Int ?? 0, contextTokens: 0, turns: 0,
      started: (header["createdAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) },
      updated: updated, id: "cursor:\(composerID)", project: workspaceName ?? workspaceFolder(header) ?? header["name"] as? String)
    session.linesAdded = header["totalLinesAdded"] as? Int ?? 0
    session.linesRemoved = header["totalLinesRemoved"] as? Int ?? 0
    session.contextFraction = (header["contextUsagePercent"] as? Double).map { min(1, max(0, $0 / 100)) }
    session.currentFile = toolRunning ? fileName(in: tool?["params"] ?? tool?["rawArgs"]) : nil
    return session
  }

  private static func workspaceFolder(_ header: [String: Any]) -> String? {
    let uri = (header["workspaceIdentifier"] as? [String: Any])?["uri"] as? [String: Any]
    return (uri?["fsPath"] as? String ?? uri?["path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
  }

  static func describe(name: String?, params: Any?) -> String? {
    guard let name, !name.isEmpty else { return nil }
    let file = fileName(in: params)
    switch name {
    case "read_file", "read_file_v2": return "Reading \(file ?? "a file")"
    case "edit_file", "edit_file_v2", "search_replace": return "Editing \(file ?? "a file")"
    case "write", "create_file": return "Writing \(file ?? "a file")"
    case "run_terminal_command_v2", "run_terminal_cmd", "run_terminal_command": return "Running a command"
    case "grep_search", "ripgrep_raw_search", "codebase_search", "semantic_search_full": return "Searching code"
    case "glob_file_search", "list_dir", "list_dir_v2", "file_search": return "Finding files"
    case "web_search", "web_fetch": return "Browsing the web"
    default: return name.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  /// `params` is a JSON string (or object) that names the file under one of a few keys.
  static func fileName(in params: Any?) -> String? {
    var object = params as? [String: Any]
    if object == nil, let text = params as? String, let data = text.data(using: .utf8) {
      object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    for key in ["relativeWorkspacePath", "targetFile", "file_path", "path", "filePath", "target_file"] {
      if let path = object?[key] as? String, !path.isEmpty { return URL(fileURLWithPath: path).lastPathComponent }
    }
    return nil
  }
}

enum CursorSessionReader {
  static func databaseURL(home: URL) -> URL {
    home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
  }

  static func read(database: URL, now: Date = .now, limit: Int = 3) -> [CodingAgentSession] {
    guard FileManager.default.isReadableFile(atPath: database.path) else { return [] }
    var handle: OpaquePointer?
    guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
      sqlite3_close(handle)
      return []
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 300)
    let cutoff = Int64((now.timeIntervalSince1970 - 300) * 1000)
    let rows = query(
      db, sql: "SELECT value FROM composerHeaders WHERE lastUpdatedAt > ? AND isArchived = 0 AND isSubagent = 0 "
        + "ORDER BY lastUpdatedAt DESC LIMIT ?", ints: [cutoff, Int64(limit)])
    return rows.compactMap { text -> CodingAgentSession? in
      guard let header = object(text), let id = header["composerId"] as? String else { return nil }
      return CursorSessionParser.session(
        header: header, bubble: newestBubble(db, composerID: id), workspaceName: nil, now: now)
    }
  }

  /// The most recently written bubble that carries a tool call, or the latest bubble.
  private static func newestBubble(_ db: OpaquePointer, composerID: String) -> [String: Any]? {
    let prefix = "bubbleId:\(composerID):"
    let rows = query(
      db, sql: "SELECT CAST(value AS TEXT) FROM cursorDiskKV WHERE key >= ? AND key < ? ORDER BY rowid DESC LIMIT 4",
      texts: [prefix, prefix + "\u{7F}"])
    let bubbles = rows.compactMap(object)
    return bubbles.first { ($0["toolFormerData"] as? [String: Any]) != nil } ?? bubbles.first
  }

  private static func object(_ text: String) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
  }

  private static func query(_ db: OpaquePointer, sql: String, ints: [Int64] = [], texts: [String] = []) -> [String] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else { return [] }
    defer { sqlite3_finalize(stmt) }
    var index: Int32 = 1
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for text in texts {
      sqlite3_bind_text(stmt, index, text, -1, transient)
      index += 1
    }
    for value in ints {
      sqlite3_bind_int64(stmt, index, value)
      index += 1
    }
    var result: [String] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      if let raw = sqlite3_column_text(stmt, 0) { result.append(String(cString: raw)) }
    }
    return result
  }
}
