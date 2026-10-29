import Foundation

/// OpenCode keeps one JSON file per session, message and message part under
/// `~/.local/share/opencode/storage/{session,message,part}`. Only the newest sessions are read.
enum OpenCodeSessionReader {
  static func defaultRoot(home: URL) -> URL {
    home.appendingPathComponent(".local/share/opencode/storage", isDirectory: true)
  }

  static func read(root: URL, now: Date = .now, limit: Int = 3) -> [CodingAgentSession] {
    let files = recentJSON(in: root.appendingPathComponent("session"), within: 300, now: now)
    return files.prefix(limit).compactMap { session(file: $0.url, modified: $0.modified, root: root) }
  }

  static func session(file: URL, modified: Date, root: URL) -> CodingAgentSession? {
    guard let info = json(file), let id = info["id"] as? String else { return nil }
    let time = info["time"] as? [String: Any]
    let updatedMS = (time?["updated"] as? Double) ?? modified.timeIntervalSince1970 * 1000
    let summary = info["summary"] as? [String: Any]
    let directory = (info["directory"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
    let messages = recentJSON(in: root.appendingPathComponent("message/\(id)"), within: 3600, now: .distantPast)
    var parsed: [(role: String, completed: Bool, id: String, model: String?, tokens: Int)] = []
    for item in messages.prefix(12).reversed() {
      guard let object = json(item.url), let messageID = object["id"] as? String else { continue }
      let msgTime = object["time"] as? [String: Any]
      let tokens = object["tokens"] as? [String: Any]
      parsed.append((
        object["role"] as? String ?? "", msgTime?["completed"] != nil, messageID,
        object["modelID"] as? String, (tokens?["output"] as? Int ?? 0) + (tokens?["reasoning"] as? Int ?? 0)))
    }
    let tokensOut = parsed.reduce(0) { $0 + $1.tokens }
    var steps: [String] = []
    var current: String?
    var currentFile: String?
    if let last = parsed.last(where: { $0.role == "assistant" }) {
      let parts = recentJSON(in: root.appendingPathComponent("part/\(last.id)"), within: 3600, now: .distantPast)
      for item in parts.prefix(10).reversed() {
        guard let part = json(item.url), part["type"] as? String == "tool" else { continue }
        let state = part["state"] as? [String: Any]
        let input = state?["input"] as? [String: Any] ?? [:]
        let step = describe(tool: part["tool"] as? String ?? "tool", input: input)
        steps.insert(step, at: 0)
        let status = state?["status"] as? String
        if status == "running" || status == "pending" {
          current = step
          currentFile = (input["filePath"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        }
      }
    }
    let lastMessage = parsed.last
    let state: CodingAgentSession.State
    if let current {
      state = .running(current)
    } else if lastMessage?.role == "assistant", lastMessage?.completed == true {
      state = .waiting
    } else {
      state = .thinking
    }
    var result = CodingAgentSession(
      tool: .openCode, model: parsed.last(where: { $0.model != nil })?.model, state: state,
      steps: Array(steps.prefix(6)), lastMessage: info["title"] as? String, outputTokens: tokensOut,
      contextTokens: 0, turns: parsed.filter { $0.role == "user" }.count,
      started: (time?["created"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
      updated: Date(timeIntervalSince1970: updatedMS / 1000), id: file.path, project: directory)
    result.linesAdded = summary?["additions"] as? Int ?? 0
    result.linesRemoved = summary?["deletions"] as? Int ?? 0
    result.currentFile = currentFile
    return result
  }

  static func describe(tool: String, input: [String: Any]) -> String {
    let file = (input["filePath"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
    switch tool {
    case "read": return "Reading \(file ?? "a file")"
    case "write": return "Writing \(file ?? "a file")"
    case "edit", "patch": return "Editing \(file ?? "a file")"
    case "bash": return "Running \((input["description"] as? String ?? input["command"] as? String ?? "command").prefix(40))"
    case "grep": return "Searching \((input["pattern"] as? String ?? "code").prefix(30))"
    case "glob", "list": return "Finding files"
    case "webfetch": return "Browsing the web"
    case "task": return "Delegating to an agent"
    default: return tool
    }
  }

  struct Entry { let url: URL; let modified: Date }

  /// `.json` files (searching up to two folders deep) newest first, and no older than `within` seconds from `now`.
  static func recentJSON(in folder: URL, within seconds: TimeInterval, now: Date) -> [Entry] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
    else { return [] }
    var entries: [Entry] = []
    for case let url as URL in enumerator {
      if enumerator.level > 2 { enumerator.skipDescendants(); continue }
      guard url.pathExtension == "json",
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
        now == .distantPast || now.timeIntervalSince(modified) < seconds
      else { continue }
      entries.append(Entry(url: url, modified: modified))
    }
    return entries.sorted { $0.modified > $1.modified }
  }

  private static func json(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url), data.count < 2_000_000 else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }
}
