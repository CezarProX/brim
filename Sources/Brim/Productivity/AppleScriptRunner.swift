import Foundation

enum AppleScriptError: Error { case failed(String) }

enum AppleScriptRunner {
  /// Runs osascript off the main thread with a time limit. Output is capped.
  static func run(_ source: String, timeout: TimeInterval = 6) async throws -> String {
    try await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = ["-e", source]
      let out = Pipe()
      let err = Pipe()
      process.standardOutput = out
      process.standardError = err
      try process.run()
      let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
      DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
      let data = out.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      killer.cancel()
      guard process.terminationStatus == 0 else {
        let message = String(decoding: err.fileHandleForReading.availableData.prefix(2000), as: UTF8.self)
        throw AppleScriptError.failed(message)
      }
      return String(decoding: data.prefix(2_000_000), as: UTF8.self)
    }.value
  }

  /// A double-quoted AppleScript string literal.
  static func quote(_ text: String) -> String {
    let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
