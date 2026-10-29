import Foundation

/// Adds Brim's hooks to Claude Code's settings.json without disturbing anything else in it.
/// Pure on JSON so it can be previewed before anything is written.
enum ClaudeHookSettings {
  static let marker = "--agent-hook"
  static let questionTimeout = 600
  static let approvalTimeout = 150

  enum MergeError: Error, Equatable { case notAnObject, hooksNotAnObject, eventNotAnArray(String) }

  struct Result: Equatable {
    /// The full file to write.
    let data: Data
    /// Human-readable lines for what was added (empty when already installed).
    let additions: [String]
    /// True when existing Brim hooks were pointed at this copy of the app (it was moved or renamed)
    /// rather than added fresh.
    var repointed = false
    var changed: Bool { !additions.isEmpty }
  }

  /// `'/Applications/Brim.app/Contents/MacOS/Brim' --agent-hook`, shell-quoted.
  static func command(executable: String) -> String {
    "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "' " + marker
  }

  private static func entries(command: String) -> [(event: String, matcher: String?, timeout: Int, summary: String)] {
    [
      ("PreToolUse", "AskUserQuestion", questionTimeout, "PreToolUse (AskUserQuestion): answer Claude's questions from the island"),
      ("PermissionRequest", nil, approvalTimeout, "PermissionRequest (all tools): Allow / Deny from the island"),
    ]
  }

  static func merge(existing: Data?, command: String) throws -> Result {
    var root: [String: Any] = [:]
    if let existing, !existing.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
      guard let object = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] else { throw MergeError.notAnObject }
      root = object
    }
    var hooks: [String: Any] = [:]
    if let current = root["hooks"] {
      guard let dict = current as? [String: Any] else { throw MergeError.hooksNotAnObject }
      hooks = dict
    }
    var additions: [String] = []
    var repointed = false
    for entry in entries(command: command) {
      var groups: [[String: Any]] = []
      if let current = hooks[entry.event] {
        guard let array = current as? [[String: Any]] else { throw MergeError.eventNotAnArray(entry.event) }
        groups = array
      }
      if groups.contains(where: { containsMarker($0) }) {
        // Already there. If an older or moved copy of the app put it there, point it at this one in
        // place instead of adding a duplicate.
        guard groups.contains(where: { containsMarker($0) && !contains(command, in: $0) }) else { continue }
        hooks[entry.event] = groups.map { containsMarker($0) ? repoint($0, to: command) : $0 }
        additions.append(entry.summary)
        repointed = true
        continue
      }
      var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": entry.timeout] as [String: Any]]]
      if let matcher = entry.matcher { group["matcher"] = matcher }
      groups.append(group)
      hooks[entry.event] = groups
      additions.append(entry.summary)
    }
    guard !additions.isEmpty else { return Result(data: existing ?? Data(), additions: []) }
    root["hooks"] = hooks
    let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    return Result(data: data + Data([0x0A]), additions: additions, repointed: repointed)
  }

  private static func repoint(_ group: [String: Any], to command: String) -> [String: Any] {
    var group = group
    group["hooks"] = ((group["hooks"] as? [[String: Any]]) ?? []).map { hook in
      guard (hook["command"] as? String)?.contains(marker) == true else { return hook }
      var hook = hook
      hook["command"] = command
      return hook
    }
    return group
  }

  private static func contains(_ command: String, in group: [String: Any]) -> Bool {
    ((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String) == command }
  }

  /// Removes only the entries Brim added.
  static func remove(from existing: Data) throws -> Data {
    guard var root = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] else { throw MergeError.notAnObject }
    guard var hooks = root["hooks"] as? [String: Any] else { return existing }
    for (event, value) in hooks {
      guard let groups = value as? [[String: Any]] else { continue }
      let kept = groups.filter { !containsMarker($0) }
      if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
    }
    if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
    return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data([0x0A])
  }

  /// Whether both hooks are present. With `command`, they must also run exactly that command, so a
  /// hook left pointing at an old copy of the app counts as not installed.
  static func isInstalled(in data: Data?, command: String? = nil) -> Bool {
    guard let data, let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let hooks = root["hooks"] as? [String: Any]
    else { return false }
    return ["PreToolUse", "PermissionRequest"].allSatisfy { event in
      ((hooks[event] as? [[String: Any]]) ?? []).contains { group in
        containsMarker(group) && (command.map { contains($0, in: group) } ?? true)
      }
    }
  }

  private static func containsMarker(_ group: [String: Any]) -> Bool {
    ((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
  }

  // MARK: Disk

  static var settingsURL: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
  }

  /// Writes the merged file after copying the old one next to it. Only called after the user confirms.
  @discardableResult
  static func install(at requested: URL = settingsURL, command: String, now: Date = Date()) throws -> (backup: URL?, result: Result) {
    let fm = FileManager.default
    let url = requested.resolvingSymlinksInPath()
    let existing = fm.contents(atPath: url.path)
    let result = try merge(existing: existing, command: command)
    guard result.changed else { return (nil, result) }
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var backup: URL?
    if existing != nil {
      let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
      let copy = url.deletingLastPathComponent().appendingPathComponent("settings.json.brim-backup-\(stamp)")
      try fm.copyItem(at: url, to: copy)
      backup = copy
    }
    let mode = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions]) ?? 0o600
    try result.data.write(to: url, options: .atomic)
    try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    return (backup, result)
  }
}
