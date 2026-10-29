import AppKit
import Foundation

/// A live Claude Code or Codex session, summarized from its local transcript.
struct CodingAgentSession: Equatable {
  enum Tool: String, CaseIterable {
    case claude = "Claude Code", codex = "Codex", cursor = "Cursor", openCode = "OpenCode", antigravity = "Antigravity"

    /// Stable key for settings, e.g. `agents.enabled.openCode`.
    var settingsID: String {
      switch self {
      case .claude: "claude"
      case .codex: "codex"
      case .cursor: "cursor"
      case .openCode: "openCode"
      case .antigravity: "antigravity"
      }
    }
  }
  /// `needsInput` means the agent is blocked on a permission prompt or question, not just finished.
  enum State: Equatable { case thinking, running(String), waiting, needsInput(String), done }

  let tool: Tool
  let model: String?
  var state: State
  /// Most recent actions first, e.g. "Read shot.png", "Bash: swift test".
  let steps: [String]
  let lastMessage: String?
  let outputTokens: Int
  let contextTokens: Int
  let turns: Int
  let started: Date?
  let updated: Date
  /// The transcript path; unique per session.
  var id: String = ""
  /// Folder the session was started in, e.g. "screenshot app".
  var project: String?
  /// The session's own name: the one given with /rename, else the title Claude Code wrote for it.
  var title: String?
  /// Lines the agent has added / removed so far, when the source reports them.
  var linesAdded: Int = 0
  var linesRemoved: Int = 0
  /// File being edited right now, e.g. "Model.swift".
  var currentFile: String?
  /// Context-window fill reported by the source (0...1), when it does not expose raw token counts.
  var contextFraction: Double?
  /// The running tool is an edit, which finishes instantly: if it stalls it is waiting on a permission prompt.
  var approvalCandidate = false

  /// Turns a stalled edit into `needsInput`. Idempotent and time-dependent, so apply it to cached sessions too.
  func promotingStalledApproval(now: Date) -> CodingAgentSession {
    guard approvalCandidate, case .running(let step) = state,
      now.timeIntervalSince(updated) > CodingAgentParser.approvalDelay
    else { return self }
    var copy = self
    copy.state = .needsInput("Approve: \(step)")
    return copy
  }

  var stateTitle: String {
    switch state {
    case .thinking: "Thinking"
    case .running(let step): step
    case .waiting: "Waiting for you"
    case .needsInput(let what): what
    case .done: "Done"
    }
  }

  var needsAttention: Bool {
    if case .needsInput = state { return true }
    return false
  }

  var hasLineChanges: Bool { linesAdded > 0 || linesRemoved > 0 }

  /// Still producing output: thinking or running a tool.
  var isWorking: Bool {
    switch state {
    case .thinking, .running: true
    case .waiting, .done, .needsInput: false
    }
  }

  /// What the notch says at a glance.
  var statusText: String {
    switch state {
    case .thinking: "Thinking"
    case .running: "Working"
    case .waiting: "Your turn"
    case .needsInput: "Needs you"
    case .done: "Done"
    }
  }

  /// The transcript's file name, which is the Claude Code session ID.
  var sessionID: String { URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent }

  func isLive(now: Date = .now) -> Bool {
    switch state {
    case .done, .waiting: now.timeIntervalSince(updated) < 60
    default: now.timeIntervalSince(updated) < 300
    }
  }
}

enum CodingAgentParser {
  /// Transcripts don't reliably record the `[1m]` model suffix, so the window is inferred:
  /// a session that has gone past the standard 200k must be running with the 1M window.
  /// Assumption: a session below 200k is treated as 200k even if it has the 1M window.
  static func contextWindow(for tokens: Int) -> Int { tokens > 200_000 ? 1_000_000 : 200_000 }
  private static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  /// Summarizes the tail of a Claude Code `.jsonl` transcript.
  static func claude(lines: [Data], modified: Date, now: Date = .now) -> CodingAgentSession? {
    var steps: [String] = []
    var lastMessage: String?
    var model: String?
    var output = 0
    var context = 0
    var turns = 0
    var started: Date?
    var lastRole: String?
    var lastStop: String?
    var pendingTool: String?
    var pendingName: String?
    var added = 0
    var removed = 0
    var currentFile: String?
    for line in lines {
      guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
        let type = object["type"] as? String, type == "user" || type == "assistant",
        let message = object["message"] as? [String: Any]
      else { continue }
      if started == nil, let stamp = object["timestamp"] as? String { started = iso.date(from: stamp) }
      let content = message["content"]
      if type == "user" {
        let isToolResult = (content as? [[String: Any]])?.contains { $0["type"] as? String == "tool_result" } ?? false
        if !isToolResult { turns += 1 }
        pendingTool = nil
        pendingName = nil
        lastRole = "user"
        continue
      }
      lastRole = "assistant"
      model = (message["model"] as? String) ?? model
      lastStop = message["stop_reason"] as? String
      if let usage = message["usage"] as? [String: Any] {
        output += usage["output_tokens"] as? Int ?? 0
        context = (usage["input_tokens"] as? Int ?? 0) + (usage["cache_read_input_tokens"] as? Int ?? 0)
          + (usage["cache_creation_input_tokens"] as? Int ?? 0)
      }
      for block in content as? [[String: Any]] ?? [] {
        switch block["type"] as? String {
        case "tool_use":
          let name = block["name"] as? String ?? "Tool"
          let input = block["input"] as? [String: Any] ?? [:]
          let step = describe(tool: name, input: input)
          steps.insert(step, at: 0)
          pendingTool = step
          pendingName = name
          let change = AgentLineCounter.change(tool: name, input: input)
          added += change.added
          removed += change.removed
          if change.touchesFile, let path = input["file_path"] as? String {
            currentFile = URL(fileURLWithPath: path).lastPathComponent
          }
        case "text":
          if let text = block["text"] as? String, !text.isEmpty { lastMessage = String(text.prefix(400)) }
        default: break
        }
      }
    }
    guard lastRole != nil else { return nil }
    let state: CodingAgentSession.State
    var editCandidate = false
    if let pendingTool, lastRole == "assistant" {
      state = .running(pendingTool)
      editCandidate = AgentLineCounter.needsApprovalWhenStalled(pendingName)
    } else if lastRole == "user" {
      state = .thinking
    } else if lastStop == "end_turn" {
      state = .waiting
    } else {
      state = .thinking
    }
    var session = CodingAgentSession(
      tool: .claude, model: model.map(prettyModel), state: state, steps: Array(steps.prefix(6)),
      lastMessage: lastMessage, outputTokens: output, contextTokens: context, turns: turns,
      started: started, updated: modified, linesAdded: added, linesRemoved: removed, currentFile: currentFile)
    session.approvalCandidate = editCandidate
    return session.promotingStalledApproval(now: now)
  }

  /// Seconds an unanswered edit tool must sit before it is treated as waiting for permission.
  static let approvalDelay: TimeInterval = 8

  /// Summarizes the tail of a Codex rollout `.jsonl`.
  static func codex(lines: [Data], modified: Date, now: Date = .now) -> CodingAgentSession? {
    var steps: [String] = []
    var lastMessage: String?
    var total = 0
    var turns = 0
    var started: Date?
    var complete = false
    var pending: String?
    var sawEvent = false
    var approval: String?
    var added = 0
    var removed = 0
    var currentFile: String?
    for line in lines {
      guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
        let payload = object["payload"] as? [String: Any]
      else { continue }
      sawEvent = true
      if started == nil, let stamp = object["timestamp"] as? String { started = iso.date(from: stamp) }
      switch payload["type"] as? String {
      case "function_call", "custom_tool_call", "local_shell_call":
        let name = payload["name"] as? String ?? "shell"
        steps.insert(name == "shell" ? "Running shell" : "Using \(name)", at: 0)
        pending = steps.first
        complete = false
      case "function_call_output", "custom_tool_call_output":
        pending = nil
        approval = nil
      case "exec_approval_request":
        approval = "Approve a command"
      case "apply_patch_approval_request":
        approval = "Approve file changes"
        let change = AgentLineCounter.patchChange(payload["changes"] as? [String: Any])
        added += change.added
        removed += change.removed
        currentFile = change.file ?? currentFile
      case "exec_command_begin", "patch_apply_begin":
        approval = nil
      case "agent_message":
        if let text = payload["message"] as? String { lastMessage = String(text.prefix(400)) }
      case "user_message":
        turns += 1
        complete = false
      case "token_count":
        let info = payload["info"] as? [String: Any]
        let usage = info?["total_token_usage"] as? [String: Any]
        total = usage?["total_tokens"] as? Int ?? total
      case "task_complete":
        complete = true
        pending = nil
      default: break
      }
    }
    guard sawEvent else { return nil }
    let state: CodingAgentSession.State =
      approval.map { .needsInput($0) } ?? (complete ? .waiting : pending.map { .running($0) } ?? .thinking)
    return CodingAgentSession(
      tool: .codex, model: nil, state: state, steps: Array(steps.prefix(6)), lastMessage: lastMessage,
      outputTokens: total, contextTokens: 0, turns: turns, started: started, updated: modified,
      linesAdded: added, linesRemoved: removed, currentFile: currentFile)
  }

  /// The first `cwd` in a transcript head. Later lines follow `cd`, so only the first names the project.
  static func project(lines: [Data]) -> String? {
    for line in lines {
      guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
      let cwd = (object["cwd"] as? String) ?? ((object["payload"] as? [String: Any])?["cwd"] as? String)
      if let cwd, !cwd.isEmpty { return URL(fileURLWithPath: cwd).lastPathComponent }
    }
    return nil
  }

  /// The session's name from a Claude Code transcript: the newest `/rename` title, else the newest title
  /// Claude Code generated. Both are re-appended as the session goes on, so the tail usually has them.
  static func title(lines: [Data]) -> String? {
    let marker = Data("-title\"".utf8)
    var custom: String?
    var generated: String?
    for line in lines where line.range(of: marker) != nil {
      guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
      switch object["type"] as? String {
      case "custom-title": custom = (object["customTitle"] as? String).flatMap(clean) ?? custom
      case "ai-title": generated = (object["aiTitle"] as? String).flatMap(clean) ?? generated
      default: break
      }
    }
    return custom ?? generated
  }

  private static func clean(_ title: String) -> String? {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : String(trimmed.prefix(80))
  }

  /// The glyph for a step described by `describe(tool:input:)`.
  static func symbol(for step: String) -> String {
    let prefixes: [(String, String)] = [
      ("Reading", "doc.text"), ("Editing", "pencil"), ("Writing", "square.and.pencil"), ("Running", "terminal"),
      ("Searching", "magnifyingglass"), ("Finding", "folder"), ("Browsing", "globe"), ("Delegating", "person.2"),
      ("Using", "wrench.and.screwdriver"),
    ]
    return prefixes.first { step.hasPrefix($0.0) }?.1 ?? "sparkle"
  }

  /// A step as the island shows it. A shell step carrying the agent's own description reads as a sentence
  /// ("Read the config"), so "Running " in front of it only doubles the verb; raw commands keep it.
  static func headline(for step: String) -> String {
    let prefix = "Running "
    guard step.hasPrefix(prefix), let first = step.dropFirst(prefix.count).first, first.isUppercase else { return step }
    return String(step.dropFirst(prefix.count))
  }

  static func describe(tool: String, input: [String: Any]) -> String {
    func base(_ key: String) -> String? {
      (input[key] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
    }
    switch tool {
    case "Read": return "Reading \(base("file_path") ?? "a file")"
    case "Write": return "Writing \(base("file_path") ?? "a file")"
    case "Edit", "MultiEdit": return "Editing \(base("file_path") ?? "a file")"
    case "Bash":
      let summary = (input["description"] as? String) ?? (input["command"] as? String) ?? "command"
      return "Running \(String(summary.prefix(40)))"
    case "Grep": return "Searching \((input["pattern"] as? String).map { String($0.prefix(30)) } ?? "code")"
    case "Glob": return "Finding files"
    case "WebFetch", "WebSearch": return "Browsing the web"
    case "Agent", "Task": return "Delegating to an agent"
    default: return tool
    }
  }

  static func prettyModel(_ id: String) -> String {
    // "claude-opus-5-5" → "Opus 5.5"
    let parts = id.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
    guard let family = parts.first else { return id }
    let version = parts.dropFirst().prefix(2).joined(separator: ".")
    return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
  }
}

/// Tracks every live Claude Code or Codex transcript on this Mac, one session per file.
@MainActor
final class CodingAgentModel: ObservableObject {
  static let shared = CodingAgentModel()
  nonisolated static let maxSessions = 4
  /// Live sessions, most recently written first.
  @Published private(set) var sessions: [CodingAgentSession] = []
  /// The session the user picked; others writing in the background don't take over the card.
  @Published private(set) var pinnedID: String?
  var session: CodingAgentSession? { Self.pick(sessions, pinned: pinnedID) }

  /// Replaces the sessions without reading transcripts: for renders and shell tests.
  func setSessionsForPreview(_ next: [CodingAgentSession]) { sessions = next }
  private var timer: Timer?
  private let queue = DispatchQueue(label: "Brim.CodingAgent", qos: .utility)
  /// Parsed transcripts by path, reused until the file changes. Only touched on `queue`.
  private let cache = TranscriptCache()
  private var reading = false

  var enabled: Bool { AppSettings.shared.codingAgentSkinEnabled }

  func start() {
    guard timer == nil, enabled else { return }
    AgentUsageStore.shared.start()
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    sessions = []
    pinnedID = nil
    AgentUsageStore.shared.stop()
  }

  /// Brings forward the app of the session that is waiting on the user, if any. True when something was activated.
  @discardableResult
  func jumpToAttention() -> Bool {
    guard let waiting = sessions.first(where: \.needsAttention) ?? session else { return false }
    return CodingAgentLocator.open(waiting)
  }

  /// Sessions that just began waiting on a permission prompt or question.
  nonisolated static func newlyNeedingAttention(previous: [CodingAgentSession], next: [CodingAgentSession]) -> [CodingAgentSession] {
    let before = Set(previous.filter(\.needsAttention).map(\.id))
    return next.filter { $0.needsAttention && !before.contains($0.id) }
  }

  private func announceAttention(_ fresh: [CodingAgentSession]) {
    guard AppSettings.shared.agentAttentionFlashEnabled, let first = fresh.first else { return }
    IslandFlashCenter.shared.show(
      "\(first.tool.rawValue) needs you", symbol: "hand.raised.fill", tint: .orange, duration: 5)
  }

  /// Pins a session; picking the pinned one again returns to following the latest.
  func select(_ id: String) {
    pinnedID = pinnedID == id ? nil : id
  }

  /// Sessions that just finished a turn: working before, waiting for the user now.
  nonisolated static func finished(previous: [CodingAgentSession], next: [CodingAgentSession]) -> [CodingAgentSession] {
    let before = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return next.filter { session in session.state == .waiting && before[session.id]?.isWorking == true }
  }

  /// The pinned session while it is live, otherwise the most recently written live one.
  nonisolated static func pick(_ sessions: [CodingAgentSession], pinned: String?, now: Date = .now) -> CodingAgentSession? {
    let live = sessions.filter { $0.isLive(now: now) }
    return live.first { $0.id == pinned } ?? live.max { $0.updated < $1.updated }
  }

  private func refresh() {
    guard !reading else { return }
    reading = true
    let cache = cache
    queue.async { [weak self] in
      let next = Self.readAll(cache: cache)
      Task { @MainActor in
        guard let self else { return }
        self.reading = false
        if self.sessions != next {
          let fresh = Self.newlyNeedingAttention(previous: self.sessions, next: next)
          self.sessions = next
          self.announceAttention(fresh)
        }
        if let pinned = self.pinnedID, !next.contains(where: { $0.id == pinned && $0.isLive() }) {
          self.pinnedID = nil
        }
      }
    }
  }

  nonisolated static func readAll(now: Date = .now, cache: TranscriptCache = TranscriptCache()) -> [CodingAgentSession] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let settings = AppSettings.shared
    let candidates =
      (settings.agentEnabled("claude")
        ? recentFiles(in: home.appendingPathComponent(".claude/projects"), depth: 2).map { ($0, CodingAgentSession.Tool.claude) } : [])
      + (settings.agentEnabled("codex")
        ? recentFiles(in: home.appendingPathComponent(".codex/sessions"), depth: 4).map { ($0, CodingAgentSession.Tool.codex) } : [])
    let recent = candidates
      .filter { now.timeIntervalSince($0.0.modified) < 300 }
      .sorted { $0.0.modified > $1.0.modified }
      .prefix(maxSessions * 2)
    let paths = Set(recent.map(\.0.url.path))
    cache.entries = cache.entries.filter { paths.contains($0.key) }
    let transcripts = recent
      .compactMap { file, tool -> CodingAgentSession? in
        if let cached = cache.entries[file.url.path], cached.modified == file.modified {
          return cached.session?.promotingStalledApproval(now: now)
        }
        var session = parse(file, tool: tool)
        // A long turn can push the title out of the tail for a while; keep the one already found.
        if session?.title == nil { session?.title = cache.entries[file.url.path]?.session?.title }
        cache.entries[file.url.path] = (file.modified, session)
        return session
      }
      .filter { $0.isLive(now: now) }
    return (transcripts + AgentSources.readAll(now: now, home: home, settings: settings))
      .filter { $0.isLive(now: now) }
      .sorted { $0.updated > $1.updated }
      .prefix(maxSessions)
      .map { $0 }
  }

  /// Transcripts parsed on the reading queue, so an unchanged file isn't re-read every poll.
  final class TranscriptCache: @unchecked Sendable {
    var entries: [String: (modified: Date, session: CodingAgentSession?)] = [:]
  }

  nonisolated private static func parse(_ file: Recent, tool: CodingAgentSession.Tool) -> CodingAgentSession? {
    let lines = tail(of: file.url, bytes: 256 * 1024)
    var session = tool == .claude
      ? CodingAgentParser.claude(lines: lines, modified: file.modified)
      : CodingAgentParser.codex(lines: lines, modified: file.modified)
    session?.id = file.url.path
    // A pasted image can make the first line longer than the head; the tail's cwd is the fallback.
    let start = head(of: file.url, bytes: 32 * 1024)
    session?.project = CodingAgentParser.project(lines: start) ?? CodingAgentParser.project(lines: lines)
    if tool == .claude { session?.title = CodingAgentParser.title(lines: lines) ?? CodingAgentParser.title(lines: start) }
    return session
  }

  private struct Recent { let url: URL; let modified: Date }

  nonisolated private static func recentFiles(in root: URL, depth: Int) -> [Recent] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else { return [] }
    var result: [Recent] = []
    let cutoff = Date().addingTimeInterval(-300)
    for case let url as URL in enumerator {
      if enumerator.level > depth { enumerator.skipDescendants(); continue }
      guard url.pathExtension == "jsonl",
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
        modified > cutoff
      else { continue }
      result.append(Recent(url: url, modified: modified))
    }
    return result
  }

  /// Reads only the start of a transcript, dropping the last partial line.
  nonisolated static func head(of url: URL, bytes: Int) -> [Data] {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: bytes) else { return [] }
    var lines = data.split(separator: UInt8(ascii: "\n")).map { Data($0) }
    if data.count == bytes, data.last != UInt8(ascii: "\n"), !lines.isEmpty { lines.removeLast() }
    return lines
  }

  /// Reads only the end of a transcript, dropping the first partial line.
  nonisolated static func tail(of url: URL, bytes: Int) -> [Data] {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
    try? handle.seek(toOffset: start)
    guard let data = try? handle.readToEnd() else { return [] }
    var lines = data.split(separator: UInt8(ascii: "\n")).map { Data($0) }
    if start > 0, !lines.isEmpty { lines.removeFirst() }
    return lines
  }
}

/// Finds the app a Claude Code session runs in (Antigravity, VS Code, Terminal, Claude), to bring it forward.
enum CodingAgentLocator {
  static let sessionsFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")

  /// Claude Code writes `~/.claude/sessions/<pid>.json` with the session ID for each running process.
  static func processID(forSession sessionID: String, in folder: URL = sessionsFolder) -> Int32? {
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    for file in files where file.pathExtension == "json" {
      guard let data = try? Data(contentsOf: file), data.count < 65_536,
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        object["sessionId"] as? String == sessionID, let pid = object["pid"] as? Int
      else { continue }
      return Int32(pid)
    }
    return nil
  }

  /// The nearest ancestor process that is a regular app.
  static func owningApp(of pid: Int32, parent: (Int32) -> Int32?, isApp: (Int32) -> Bool) -> Int32? {
    var current = pid
    for _ in 0..<32 {
      if isApp(current) { return current }
      guard let next = parent(current), next > 1, next != current else { return nil }
      current = next
    }
    return nil
  }

  static func parentProcess(of pid: Int32) -> Int32? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    return info.kp_eproc.e_ppid
  }

  /// Brings the session's app forward: the process that owns a Claude Code session, else the agent's own
  /// app by bundle id, else a terminal. False when nothing is running to activate.
  @MainActor
  @discardableResult
  static func open(_ session: CodingAgentSession, running: (String) -> NSRunningApplication? = {
    NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
  }) -> Bool {
    if session.tool == .claude, let pid = processID(forSession: session.sessionID),
      let appPID = owningApp(of: pid, parent: parentProcess, isApp: {
        NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular
      }),
      let app = NSRunningApplication(processIdentifier: appPID)
    {
      return app.activate(options: [])
    }
    var bundles = AgentBrand.bundleIDs(session.tool)
    if session.tool == .claude || session.tool == .codex || session.tool == .openCode { bundles += AgentBrand.terminalBundleIDs }
    for bundle in bundles {
      if let app = running(bundle) { return app.activate(options: []) }
    }
    return false
  }
}
