import Foundation

/// Command-line tools Brim can use when they are already installed. It never installs them:
/// without them Transform uses Apple's frameworks only.
enum OptionalTool: String, CaseIterable, Identifiable, Sendable {
  case ffmpeg, ghostscript, cwebp
  var id: String { rawValue }

  var executable: String {
    switch self {
    case .ffmpeg: "ffmpeg"
    case .ghostscript: "gs"
    case .cwebp: "cwebp"
    }
  }

  var title: String {
    switch self {
    case .ffmpeg: "FFmpeg"
    case .ghostscript: "Ghostscript"
    case .cwebp: "cwebp"
    }
  }

  /// What finding the tool unlocks.
  var unlocks: String {
    switch self {
    case .ffmpeg: "WebM and MKV video output"
    case .ghostscript: "PDF compression that keeps text selectable"
    case .cwebp: "WebP image output"
    }
  }

  var brewFormula: String {
    switch self {
    case .ffmpeg: "ffmpeg"
    case .ghostscript: "ghostscript"
    case .cwebp: "webp"
    }
  }
}

enum OptionalTools {
  /// Homebrew (Apple silicon and Intel) and MacPorts.
  static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]

  /// Pure lookup: the first directory that holds an executable with the tool's name.
  static func locate(
    _ tool: OptionalTool, in directories: [String] = searchDirectories,
    isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
  ) -> URL? {
    for directory in directories {
      let path = (directory as NSString).appendingPathComponent(tool.executable)
      if isExecutable(path) { return URL(fileURLWithPath: path) }
    }
    return nil
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var cache: [OptionalTool: (url: URL?, checked: Date)] = [:]

  /// Cached for 30 seconds so installing a tool is noticed without a restart.
  static func url(for tool: OptionalTool, now: Date = .now) -> URL? {
    lock.lock()
    defer { lock.unlock() }
    if let hit = cache[tool], now.timeIntervalSince(hit.checked) < 30 { return hit.url }
    let found = locate(tool)
    cache[tool] = (found, now)
    return found
  }

  static func isAvailable(_ tool: OptionalTool) -> Bool { url(for: tool) != nil }

  static func invalidate() {
    lock.lock()
    cache = [:]
    lock.unlock()
  }
}
