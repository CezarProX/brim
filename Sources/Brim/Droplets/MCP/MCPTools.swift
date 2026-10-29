import Foundation

/// One tool Brim offers to AI apps over MCP.
struct MCPToolSpec {
  let name: String
  /// Plain-language label for the settings list.
  let title: String
  /// What it exposes, shown next to its switch so consent is informed.
  let detail: String
  let description: String
  /// JSON Schema properties and the required list.
  let properties: [String: [String: Any]]
  let required: [String]

  var inputSchema: [String: Any] {
    ["type": "object", "properties": properties, "required": required]
  }
}

enum MCPCatalog {
  static let tools: [MCPToolSpec] = [
    MCPToolSpec(
      name: "clipboard_search", title: "Search clipboard history",
      detail: "Reads text you copied recently (blurred items are hidden).",
      description: "Search Brim's clipboard history for text containing a query. Returns the newest matches.",
      properties: ["query": ["type": "string", "description": "Text to look for; empty returns the newest items."],
                   "limit": ["type": "integer", "description": "Maximum results, 1 to 20 (default 5)."]],
      required: []),
    MCPToolSpec(
      name: "tray_list", title: "List the file tray",
      detail: "Shows the names and paths of files parked in the tray.",
      description: "List the files currently held in Brim's notch file tray.",
      properties: [:], required: []),
    MCPToolSpec(
      name: "tray_add", title: "Add files to the tray",
      detail: "Puts existing files on this Mac into the tray.",
      description: "Add existing files, by absolute path, to Brim's notch file tray.",
      properties: ["paths": ["type": "array", "items": ["type": "string"], "description": "Absolute file paths."]], required: ["paths"]),
    MCPToolSpec(
      name: "now_playing", title: "Read now playing",
      detail: "Shows the current song, artist and whether it is playing.",
      description: "Report the track currently playing on this Mac.",
      properties: [:], required: []),
    MCPToolSpec(
      name: "media_control", title: "Control playback",
      detail: "Can play, pause, skip and go back.",
      description: "Control media playback: playPause, next or previous.",
      properties: ["action": ["type": "string", "description": "playPause, next or previous."]], required: ["action"]),
    MCPToolSpec(
      name: "timers", title: "Timers",
      detail: "Reads running timers and can start a focus timer.",
      description: "List running timers, or start a focus timer by passing minutes.",
      properties: ["start_minutes": ["type": "integer", "description": "Optional: start a focus timer of this many minutes (1 to 600)."]],
      required: []),
    MCPToolSpec(
      name: "calendar_upcoming", title: "Upcoming calendar events",
      detail: "Reads event titles and times for the next two weeks.",
      description: "List upcoming calendar events and due reminders from the next two weeks.",
      properties: ["limit": ["type": "integer", "description": "Maximum items, 1 to 30 (default 10)."]], required: []),
    MCPToolSpec(
      name: "notes", title: "Island notes",
      detail: "Reads your island notes and can add a new one.",
      description: "List Brim island notes, or add one by passing text.",
      properties: ["add_text": ["type": "string", "description": "Optional: text of a new note to create."]], required: []),
    MCPToolSpec(
      name: "transform", title: "Open the Transform panel",
      detail: "Opens the island's Transform panel for files you name; you still choose and run the operation.",
      description: "Open Brim's Transform panel (compress, convert, resize) for the given files. The user picks the operation.",
      properties: ["paths": ["type": "array", "items": ["type": "string"], "description": "Absolute file paths."]], required: ["paths"]),
  ]

  static func spec(named name: String) -> MCPToolSpec? { tools.first { $0.name == name } }
}

/// The consent gate: a tool runs only when the user switched it on in settings.
enum MCPGate {
  enum Decision: Equatable {
    case allowed
    case unknownTool
    case denied
  }

  static func decide(tool: String, allowed: Set<String>, serverEnabled: Bool) -> Decision {
    guard MCPCatalog.spec(named: tool) != nil else { return .unknownTool }
    return serverEnabled && allowed.contains(tool) ? .allowed : .denied
  }

  static func deniedMessage(tool: String, serverEnabled: Bool) -> String {
    serverEnabled
      ? "The “\(tool)” tool is turned off. The user can allow it in Brim > Settings > Home & Widgets > MCP Server."
      : "Brim’s MCP server is turned off. The user can enable it in Brim > Settings > Home & Widgets > MCP Server."
  }
}
