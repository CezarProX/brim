import Foundation

/// Antigravity's conversation logs are opaque protobufs, but each conversation also writes plain-text artifacts to
/// `~/.gemini/antigravity/brain/<conversation>/`: `task.md` (a `[ ]` / `[/]` / `[x]` checklist) and `*.metadata.json`
/// (`summary`, `updatedAt`). The session state is derived from those.
enum AntigravitySessionParser {
  struct Checklist: Equatable {
    var title: String?
    var inProgress: String?
    var open = 0
    var done = 0
  }

  static func checklist(_ markdown: String) -> Checklist {
    var result = Checklist()
    for raw in markdown.split(separator: "\n") {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if result.title == nil, line.hasPrefix("# ") { result.title = String(line.dropFirst(2)) }
      guard line.hasPrefix("- [") || line.hasPrefix("* ["), line.count > 5 else { continue }
      let mark = line[line.index(line.startIndex, offsetBy: 3)]
      let text = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
      switch mark {
      case "x", "X": result.done += 1
      case "/": result.inProgress = result.inProgress ?? text; result.open += 1
      default: result.open += 1
      }
    }
    return result
  }

  /// First backticked path in a checklist item, e.g. "Edit `src/App.tsx`".
  static func file(in text: String?) -> String? {
    guard let text, let start = text.firstIndex(of: "`") else { return nil }
    let rest = text[text.index(after: start)...]
    guard let end = rest.firstIndex(of: "`") else { return nil }
    let candidate = String(rest[..<end])
    return candidate.contains(".") ? URL(fileURLWithPath: candidate).lastPathComponent : nil
  }

  static func session(
    id: String, task: String?, summary: String?, updated: Date, now: Date = .now
  ) -> CodingAgentSession? {
    let list = checklist(task ?? "")
    guard list.title != nil || summary != nil else { return nil }
    let lowered = summary?.lowercased() ?? ""
    let asksUser = lowered.contains("waiting for user") || lowered.contains("waiting for your")
      || lowered.contains("awaiting user") || lowered.contains("awaiting your") || lowered.contains("needs your")
    let state: CodingAgentSession.State
    if asksUser && list.open > 0 {
      state = .needsInput("Waiting for your review")
    } else if let current = list.inProgress, now.timeIntervalSince(updated) < 120 {
      state = .running(current)
    } else if list.open > 0 && now.timeIntervalSince(updated) < 20 {
      state = .thinking
    } else {
      state = .waiting
    }
    var session = CodingAgentSession(
      tool: .antigravity, model: nil, state: state, steps: list.inProgress.map { [$0] } ?? [],
      lastMessage: summary, outputTokens: 0, contextTokens: 0, turns: 0, started: nil, updated: updated,
      id: "antigravity:\(id)", project: list.title)
    session.currentFile = file(in: list.inProgress)
    return session
  }
}

enum AntigravitySessionReader {
  static func brainFolders(home: URL) -> [URL] {
    [".gemini/antigravity/brain", ".gemini/antigravity-ide/brain"].map {
      home.appendingPathComponent($0, isDirectory: true)
    }
  }

  static func read(brains: [URL], now: Date = .now, limit: Int = 2) -> [CodingAgentSession] {
    let fm = FileManager.default
    var found: [(URL, Date)] = []
    for brain in brains {
      for folder in (try? fm.contentsOfDirectory(at: brain, includingPropertiesForKeys: nil)) ?? [] {
        guard let updated = newest(in: folder), now.timeIntervalSince(updated) < 300 else { continue }
        found.append((folder, updated))
      }
    }
    return found.sorted { $0.1 > $1.1 }.prefix(limit).compactMap { folder, updated in
      let task = try? String(contentsOf: folder.appendingPathComponent("task.md"), encoding: .utf8)
      let metadata = (try? Data(contentsOf: folder.appendingPathComponent("task.md.metadata.json")))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      return AntigravitySessionParser.session(
        id: folder.lastPathComponent, task: task.map { String($0.prefix(20_000)) },
        summary: metadata?["summary"] as? String, updated: updated, now: now)
    }
  }

  private static func newest(in folder: URL) -> Date? {
    ["task.md", "task.md.metadata.json", "implementation_plan.md", "walkthrough.md"].compactMap {
      try? folder.appendingPathComponent($0).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }.max()
  }
}
