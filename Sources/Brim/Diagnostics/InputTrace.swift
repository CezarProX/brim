import AppKit
import os

/// Input tracing for diagnosing clicks that never reach the capture overlay or the tour. Off unless
/// asked for (`BRIM_INPUT_TRACE=1` or `defaults write io.github.cezarprox.brim debugInputTrace -bool YES`):
/// it records every click, so it must never run for ordinary users.
/// Read with: log show --last 5m --predicate 'subsystem == "io.github.cezarprox.brim" && category == "input"'
enum InputTrace {
  static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "input")
  static let isEnabled = ProcessInfo.processInfo.environment["BRIM_INPUT_TRACE"] != nil
    || UserDefaults.standard.bool(forKey: "debugInputTrace")
  /// The log grows forever while tracing; past this it starts over.
  private static let maximumBytes = 1_000_000

  static func event(_ where: String, _ event: NSEvent, window: NSWindow?) {
    guard isEnabled else { return }
    let point = NSEvent.mouseLocation
    note("\(`where`) type=\(event.type.rawValue) loc=(\(Int(point.x)),\(Int(point.y))) key=\(window?.isKeyWindow ?? false) appActive=\(NSApp.isActive) level=\(window?.level.rawValue ?? -1)")
  }

  static func note(_ message: String) {
    guard isEnabled else { return }
    log.notice("\(message, privacy: .public)")
    append(message)
  }

  private static let fileURL: URL = {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Brim")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("input.log")
  }()

  private static func append(_ line: String) {
    let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
    guard let data = "\(stamp) \(line)\n".data(using: .utf8) else { return }
    let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
    if size > maximumBytes { try? FileManager.default.removeItem(at: fileURL) }
    if let handle = try? FileHandle(forWritingTo: fileURL) {
      handle.seekToEndOfFile(); handle.write(data); try? handle.close()
    } else {
      try? data.write(to: fileURL)
    }
  }

  private static var monitor: Any?

  /// Logs every mouse-down that reaches this app at all, and which window AppKit routes it to.
  static func install() {
    guard isEnabled else {
      // Builds before tracing became opt-in left a log of every click behind; remove it.
      try? FileManager.default.removeItem(at: fileURL)
      return
    }
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
      let title = event.window.map { String(describing: type(of: $0)) } ?? "nil"
      note("app.local type=\(event.type.rawValue) window=\(title) n=\(event.windowNumber) active=\(NSApp.isActive)")
      return event
    }
  }
}
