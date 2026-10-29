import Foundation
import SQLite3
import Testing

@testable import Brim

struct AgentSourcesTests {
  private func temp() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("agents-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func write(_ object: Any, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: object).write(to: url)
  }

  // MARK: Cursor

  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func header(_ extra: [String: Any] = [:], ageSeconds: Double = 2) -> [String: Any] {
    var base: [String: Any] = [
      "composerId": "abc", "name": "Fix login", "lastUpdatedAt": (now.timeIntervalSince1970 - ageSeconds) * 1000,
      "createdAt": (now.timeIntervalSince1970 - 600) * 1000, "totalLinesAdded": 42, "totalLinesRemoved": 7,
      "contextUsagePercent": 36.5, "hasBlockingPendingActions": false, "isArchived": false, "isDraft": false,
      "subtitle": "Edited auth.ts",
    ]
    for (key, value) in extra { base[key] = value }
    return base
  }

  @Test func cursorRunningToolReadsFileAndLines() throws {
    let bubble: [String: Any] = [
      "toolFormerData": ["name": "edit_file_v2", "status": "loading", "params": #"{"relativeWorkspacePath":"src/auth.ts"}"#],
      "tokenCount": ["inputTokens": 100, "outputTokens": 250],
    ]
    let session = try #require(CursorSessionParser.session(header: header(), bubble: bubble, workspaceName: "web", now: now))
    #expect(session.tool == .cursor)
    #expect(session.state == .running("Editing auth.ts"))
    #expect(session.currentFile == "auth.ts")
    #expect(session.linesAdded == 42 && session.linesRemoved == 7)
    #expect(session.outputTokens == 250)
    #expect(session.contextFraction == 0.365)
    #expect(session.project == "web")
  }

  @Test func cursorBlockingActionsMeansNeedsInput() throws {
    let bubble: [String: Any] = ["toolFormerData": ["name": "run_terminal_command_v2", "status": "loading"]]
    let session = try #require(
      CursorSessionParser.session(header: header(["hasBlockingPendingActions": true]), bubble: bubble, workspaceName: nil, now: now))
    #expect(session.needsAttention)
    #expect(session.state == .needsInput("Approve: Running a command"))
    #expect(!session.isWorking)
  }

  @Test func cursorClassifiesThinkingAndDone() throws {
    let fresh = try #require(CursorSessionParser.session(header: header(), bubble: nil, workspaceName: nil, now: now))
    #expect(fresh.state == .thinking)
    let idle = try #require(CursorSessionParser.session(header: header(ageSeconds: 90), bubble: nil, workspaceName: nil, now: now))
    #expect(idle.state == .waiting)
    #expect(CursorSessionParser.session(header: header(["isArchived": true]), bubble: nil, workspaceName: nil, now: now) == nil)
    #expect(CursorSessionParser.session(header: header(["isDraft": true]), bubble: nil, workspaceName: nil, now: now) == nil)
  }

  @Test func cursorReaderQueriesARealSQLiteFile() throws {
    let dir = try temp()
    let path = dir.appendingPathComponent("state.vscdb").path
    var db: OpaquePointer?
    #expect(sqlite3_open(path, &db) == SQLITE_OK)
    let recent = (now.timeIntervalSince1970 - 5) * 1000
    let json = String(
      data: try JSONSerialization.data(withJSONObject: header(["lastUpdatedAt": recent])), encoding: .utf8)!.replacingOccurrences(of: "'", with: "''")
    let bubble = #"{"toolFormerData":{"name":"read_file_v2","status":"loading","params":"{\"targetFile\":\"/x/App.swift\"}"}}"#
    let statements = [
      "CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, workspaceId TEXT, createdAt INTEGER, lastUpdatedAt INTEGER, isArchived INTEGER, isSubagent INTEGER, recency INTEGER, checkpointAt INTEGER, value TEXT, subagentTypeName TEXT)",
      "CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)",
      "INSERT INTO composerHeaders (composerId, lastUpdatedAt, isArchived, isSubagent, value) VALUES ('abc', \(Int64(recent)), 0, 0, '\(json)')",
      "INSERT INTO composerHeaders (composerId, lastUpdatedAt, isArchived, isSubagent, value) VALUES ('old', 1000, 0, 0, '{\"composerId\":\"old\"}')",
      "INSERT INTO cursorDiskKV (key, value) VALUES ('bubbleId:abc:1', '\(bubble.replacingOccurrences(of: "'", with: "''"))')",
    ]
    for sql in statements { #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "\(sql.prefix(40))") }
    sqlite3_close(db)
    let sessions = CursorSessionReader.read(database: URL(fileURLWithPath: path), now: now)
    #expect(sessions.count == 1)
    #expect(sessions.first?.state == .running("Reading App.swift"))
    #expect(CursorSessionReader.read(database: dir.appendingPathComponent("missing.vscdb"), now: now).isEmpty)
  }

  // MARK: OpenCode

  @Test func openCodeSessionReadsToolFileLinesAndTokens() throws {
    let root = try temp()
    let updated = Date().timeIntervalSince1970 * 1000
    try write(
      ["id": "ses_1", "title": "Refactor", "directory": "/work/site", "time": ["created": updated - 60_000, "updated": updated],
       "summary": ["additions": 12, "deletions": 3, "files": 2]], to: root.appendingPathComponent("session/proj/ses_1.json"))
    try write(["id": "msg_u", "role": "user", "time": ["created": updated - 50_000]], to: root.appendingPathComponent("message/ses_1/msg_u.json"))
    try write(
      ["id": "msg_a", "role": "assistant", "modelID": "claude-sonnet", "time": ["created": updated - 40_000],
       "tokens": ["input": 10, "output": 300, "reasoning": 20]], to: root.appendingPathComponent("message/ses_1/msg_a.json"))
    try write(
      ["id": "prt_1", "type": "tool", "tool": "edit",
       "state": ["status": "running", "input": ["filePath": "/work/site/index.html"]]],
      to: root.appendingPathComponent("part/msg_a/prt_1.json"))
    let session = try #require(OpenCodeSessionReader.read(root: root).first)
    #expect(session.tool == .openCode)
    #expect(session.state == .running("Editing index.html"))
    #expect(session.currentFile == "index.html")
    #expect(session.linesAdded == 12 && session.linesRemoved == 3)
    #expect(session.outputTokens == 320)
    #expect(session.project == "site")
    #expect(session.model == "claude-sonnet")
    #expect(OpenCodeSessionReader.read(root: try temp()).isEmpty)
  }

  @Test func openCodeCompletedAssistantMessageWaitsForYou() throws {
    let root = try temp()
    let updated = Date().timeIntervalSince1970 * 1000
    try write(["id": "ses_2", "time": ["updated": updated]], to: root.appendingPathComponent("session/p/ses_2.json"))
    try write(
      ["id": "msg_a", "role": "assistant", "time": ["created": updated - 10_000, "completed": updated - 1000]],
      to: root.appendingPathComponent("message/ses_2/msg_a.json"))
    #expect(OpenCodeSessionReader.read(root: root).first?.state == .waiting)
  }

  // MARK: Antigravity

  @Test func antigravityChecklistDrivesState() throws {
    let task = "# Redesign Cards\n\n- [x] Pick style\n- [/] Edit `src/Process.tsx`\n- [ ] Verify\n"
    let list = AntigravitySessionParser.checklist(task)
    #expect(list.title == "Redesign Cards")
    #expect(list.inProgress == "Edit `src/Process.tsx`")
    #expect(list.done == 1 && list.open == 2)
    let running = try #require(
      AntigravitySessionParser.session(id: "c1", task: task, summary: "Working", updated: now.addingTimeInterval(-5), now: now))
    #expect(running.state == .running("Edit `src/Process.tsx`"))
    #expect(running.currentFile == "Process.tsx")
    #expect(running.project == "Redesign Cards")
    let waiting = try #require(
      AntigravitySessionParser.session(
        id: "c1", task: task, summary: "Currently waiting for user to select an option.", updated: now, now: now))
    #expect(waiting.needsAttention)
    let done = try #require(
      AntigravitySessionParser.session(id: "c1", task: "# T\n- [x] a\n", summary: "Done", updated: now, now: now))
    #expect(done.state == .waiting)
  }

  @Test func antigravityReaderFindsRecentBrainFolders() throws {
    let brain = try temp()
    let folder = brain.appendingPathComponent("conv-1")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "# Ship it\n- [/] Edit `a.swift`\n".write(to: folder.appendingPathComponent("task.md"), atomically: true, encoding: .utf8)
    try write(["summary": "Working", "updatedAt": "2026-10-01T00:00:00Z"], to: folder.appendingPathComponent("task.md.metadata.json"))
    let sessions = AntigravitySessionReader.read(brains: [brain])
    #expect(sessions.count == 1)
    #expect(sessions.first?.id == "antigravity:conv-1")
  }
}
