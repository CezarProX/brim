import AppKit
import SwiftUI

/// Executes MCP tool calls inside the running app. Every call goes through the consent gate and
/// is shown as an island flash, whether it runs or is refused.
@MainActor
final class MCPAppService {
  static let shared = MCPAppService()
  private let settings = AppSettings.shared

  func handle(tool: String, arguments: [String: Any]) async -> MCPToolOutcome {
    let enabled = settings.mcpEnabled
    switch MCPGate.decide(tool: tool, allowed: settings.mcpAllowedTools, serverEnabled: enabled) {
    case .unknownTool:
      return MCPToolOutcome(text: "Unknown tool “\(tool)”.", isError: true)
    case .denied:
      let title = MCPCatalog.spec(named: tool)?.title ?? tool
      IslandFlashCenter.shared.show("AI blocked", symbol: "hand.raised.fill", tint: .orange, detail: title)
      return MCPToolOutcome(text: MCPGate.deniedMessage(tool: tool, serverEnabled: enabled), isError: true)
    case .allowed:
      let title = MCPCatalog.spec(named: tool)?.title ?? tool
      IslandFlashCenter.shared.show("AI used", symbol: "sparkles", tint: .purple, detail: title)
      return await run(tool, arguments)
    }
  }

  private func run(_ tool: String, _ arguments: [String: Any]) async -> MCPToolOutcome {
    switch tool {
    case "clipboard_search": return clipboardSearch(arguments)
    case "tray_list": return trayList()
    case "tray_add": return trayAdd(arguments)
    case "now_playing": return nowPlaying()
    case "media_control": return mediaControl(arguments)
    case "timers": return timers(arguments)
    case "calendar_upcoming": return calendar(arguments)
    case "notes": return notes(arguments)
    case "transform": return transform(arguments)
    default: return MCPToolOutcome(text: "Unknown tool “\(tool)”.", isError: true)
    }
  }

  // MARK: Tools

  private func clipboardSearch(_ args: [String: Any]) -> MCPToolOutcome {
    let query = (args["query"] as? String ?? "").lowercased()
    let limit = Self.clamp(args["limit"], 1...20, default: 5)
    let hits = ClipboardStore.shared.entries.filter { entry in
      guard !entry.isBlurred, entry.kind != .image else { return false }
      let haystack = ((entry.text ?? "") + " " + (entry.ocrText ?? "")).lowercased()
      return query.isEmpty || haystack.contains(query)
    }
    .prefix(limit)
    guard !hits.isEmpty else { return MCPToolOutcome(text: "No matching clipboard items.") }
    let formatter = ISO8601DateFormatter()
    return MCPToolOutcome(text: hits.map { "[\(formatter.string(from: $0.date))] \(String(($0.text ?? "").prefix(400)))" }.joined(separator: "\n---\n"))
  }

  private func trayList() -> MCPToolOutcome {
    let store = FileTrayStore.shared
    guard !store.items.isEmpty else { return MCPToolOutcome(text: "The tray is empty.") }
    return MCPToolOutcome(text: store.items.map { store.url(for: $0).path }.joined(separator: "\n"))
  }

  private func trayAdd(_ args: [String: Any]) -> MCPToolOutcome {
    let urls = Self.absolutePaths(args["paths"])
    guard !urls.isEmpty else { return MCPToolOutcome(text: "Pass absolute paths of existing files.", isError: true) }
    let added = FileTrayStore.shared.add(urls)
    return MCPToolOutcome(text: "Added \(added) of \(urls.count) file(s) to the tray.")
  }

  private func nowPlaying() -> MCPToolOutcome {
    guard let track = NowPlayingModel.shared.track?.snapshot else { return MCPToolOutcome(text: "Nothing is playing.") }
    return MCPToolOutcome(text: "\(track.isPlaying ? "Playing" : "Paused"): \(track.title) by \(track.artist) (\(track.album)) in \(track.source.rawValue)")
  }

  private func mediaControl(_ args: [String: Any]) -> MCPToolOutcome {
    let player = NowPlayingModel.shared
    switch args["action"] as? String {
    case "playPause": player.playPause()
    case "next": player.next()
    case "previous": player.previous()
    default: return MCPToolOutcome(text: "action must be playPause, next or previous.", isError: true)
    }
    return MCPToolOutcome(text: "Done.")
  }

  private func timers(_ args: [String: Any]) -> MCPToolOutcome {
    let focus = FocusTimerModel.shared
    if let minutes = args["start_minutes"] as? Int {
      guard (1...FocusTimerModel.maximumMinutes).contains(minutes) else {
        return MCPToolOutcome(text: "start_minutes must be between 1 and \(FocusTimerModel.maximumMinutes).", isError: true)
      }
      focus.start(minutes: minutes)
      return MCPToolOutcome(text: "Started a \(minutes)-minute focus timer.")
    }
    var lines: [String] = []
    if focus.deadline != nil || focus.isPaused {
      lines.append("Focus timer: \(Int(focus.remaining() / 60)) min left\(focus.isPaused ? " (paused)" : "")")
    }
    if let native = NativeTimerModel.shared.activeTimer {
      lines.append("\(native.title): \(Int(native.remaining() / 60)) min left\(native.isPaused ? " (paused)" : "")")
    }
    return MCPToolOutcome(text: lines.isEmpty ? "No timers running." : lines.joined(separator: "\n"))
  }

  private func calendar(_ args: [String: Any]) -> MCPToolOutcome {
    let limit = Self.clamp(args["limit"], 1...30, default: 10)
    let formatter = ISO8601DateFormatter()
    let items = CalendarActivityModel.shared.agenda.flatMap(\.items).prefix(limit)
    guard !items.isEmpty else { return MCPToolOutcome(text: "No upcoming events (or Calendar access is off).") }
    return MCPToolOutcome(text: items.map { "\(formatter.string(from: $0.start)) \($0.kind == .reminder ? "[reminder] " : "")\($0.title)" }.joined(separator: "\n"))
  }

  private func notes(_ args: [String: Any]) -> MCPToolOutcome {
    let model = NotesModel.shared
    if let text = args["add_text"] as? String, !text.isEmpty {
      let note = model.create()
      model.update(note.id, text: text)
      return MCPToolOutcome(text: "Added a note.")
    }
    guard !model.notes.isEmpty else { return MCPToolOutcome(text: "No notes.") }
    return MCPToolOutcome(text: model.notes.prefix(20).map { String($0.text.prefix(400)) }.joined(separator: "\n---\n"))
  }

  private func transform(_ args: [String: Any]) -> MCPToolOutcome {
    let urls = Self.absolutePaths(args["paths"])
    guard !urls.isEmpty else { return MCPToolOutcome(text: "Pass absolute paths of existing files.", isError: true) }
    NotchShelfController.shared.presentConvert(urls)
    return MCPToolOutcome(text: "Opened the Transform panel for \(urls.count) file(s). The user chooses what to do.")
  }

  // MARK: Argument helpers

  nonisolated static func clamp(_ value: Any?, _ range: ClosedRange<Int>, default fallback: Int) -> Int {
    guard let number = value as? Int else { return fallback }
    return min(range.upperBound, max(range.lowerBound, number))
  }

  /// Absolute paths of files that exist, as URLs. Relative paths and directories are ignored.
  nonisolated static func absolutePaths(_ value: Any?) -> [URL] {
    guard let paths = value as? [String] else { return [] }
    return paths.prefix(50).compactMap { path in
      var isDirectory: ObjCBool = false
      guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue
      else { return nil }
      return URL(fileURLWithPath: path)
    }
  }
}
