import Foundation

/// Counts lines an agent added or removed from the tool calls it makes, and says which tools stall on permission.
enum AgentLineCounter {
  struct Change: Equatable {
    var added = 0
    var removed = 0
    var touchesFile = false
    var file: String?
  }

  static func lineCount(_ text: String?) -> Int {
    guard let text, !text.isEmpty else { return 0 }
    return text.split(separator: "\n", omittingEmptySubsequences: false).count
  }

  /// Lines changed by one Claude Code tool call (Edit, MultiEdit, Write, NotebookEdit).
  static func change(tool: String, input: [String: Any]) -> Change {
    switch tool {
    case "Edit":
      return Change(
        added: lineCount(input["new_string"] as? String), removed: lineCount(input["old_string"] as? String),
        touchesFile: true)
    case "MultiEdit":
      let edits = input["edits"] as? [[String: Any]] ?? []
      return Change(
        added: edits.reduce(0) { $0 + lineCount($1["new_string"] as? String) },
        removed: edits.reduce(0) { $0 + lineCount($1["old_string"] as? String) }, touchesFile: true)
    case "Write":
      return Change(added: lineCount(input["content"] as? String), removed: 0, touchesFile: true)
    case "NotebookEdit":
      return Change(added: lineCount(input["new_source"] as? String), removed: 0, touchesFile: true)
    default:
      return Change()
    }
  }

  /// Edits finish instantly; if one sits unanswered the agent is waiting for the user's permission.
  static func needsApprovalWhenStalled(_ tool: String?) -> Bool {
    guard let tool else { return false }
    return ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(tool)
  }

  /// Lines in a Codex `apply_patch` approval request: `{path: {add: {content}} | {update: {unified_diff}}}`.
  static func patchChange(_ changes: [String: Any]?) -> Change {
    var result = Change()
    for (path, value) in (changes ?? [:]).sorted(by: { $0.key < $1.key }) {
      guard let entry = value as? [String: Any] else { continue }
      result.file = result.file ?? URL(fileURLWithPath: path).lastPathComponent
      if let add = entry["add"] as? [String: Any] {
        result.added += lineCount(add["content"] as? String)
      } else if let update = entry["update"] as? [String: Any], let diff = update["unified_diff"] as? String {
        for line in diff.split(separator: "\n") {
          if line.hasPrefix("+") && !line.hasPrefix("+++") { result.added += 1 }
          if line.hasPrefix("-") && !line.hasPrefix("---") { result.removed += 1 }
        }
      } else if entry["delete"] != nil {
        result.removed += 1
      }
    }
    return result
  }
}
