import Foundation

/// Copy-paste setup instructions for AI apps. Brim never edits their config files.
enum MCPSetupText {
  static var executable: String { Bundle.main.executablePath ?? "/Applications/Brim.app/Contents/MacOS/Brim" }

  /// JSON object for Claude Desktop and Cursor style `mcpServers` configs.
  static func configJSON(executable: String) -> String {
    let object: [String: Any] = ["mcpServers": ["brim": ["command": executable, "args": ["--mcp"]]]]
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    return String(decoding: data, as: UTF8.self)
  }

  static func claudeCodeCommand(executable: String) -> String {
    "claude mcp add brim -- \(shellQuoted(executable)) --mcp"
  }

  static func shellQuoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

  static func instructions(executable: String) -> String {
    """
    Claude Code (Terminal):
    \(claudeCodeCommand(executable: executable))

    Claude Desktop: Settings > Developer > Edit Config, then merge this into claude_desktop_config.json and restart Claude:
    \(configJSON(executable: executable))

    Cursor: add the same block to ~/.cursor/mcp.json (or Settings > MCP > Add new server).

    Keep Brim running. Each tool stays off until you allow it below.
    """
  }
}
