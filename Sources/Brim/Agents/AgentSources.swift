import Foundation

/// Sessions from agents that don't write a single JSONL transcript: Cursor (SQLite), OpenCode (JSON tree)
/// and Antigravity (markdown artifacts). Each source honors its per-agent setting.
enum AgentSources {
  static func readAll(now: Date, home: URL, settings: AppSettings) -> [CodingAgentSession] {
    var result: [CodingAgentSession] = []
    if settings.agentEnabled("cursor") {
      result += CursorSessionReader.read(database: CursorSessionReader.databaseURL(home: home), now: now)
    }
    if settings.agentEnabled("openCode") {
      result += OpenCodeSessionReader.read(root: OpenCodeSessionReader.defaultRoot(home: home), now: now)
    }
    if settings.agentEnabled("antigravity") {
      result += AntigravitySessionReader.read(brains: AntigravitySessionReader.brainFolders(home: home), now: now)
    }
    return result
  }
}
