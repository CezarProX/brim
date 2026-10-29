// MessagesReply.swift
// Brim
//
// Inline reply for Messages. The reply text and recipient are NEVER spliced into AppleScript
// source: the script is a fixed string with an `on run argv` handler, and the values are passed
// as separate process arguments to osascript. Needs Automation consent for Messages.

import Foundation

enum MessagesReply {
  /// Fixed source. Finds a one-to-one chat whose participant matches the notification title
  /// (full name, name or handle); falls back to a buddy lookup. Group chats match by chat name.
  static let scriptLines: [String] = [
    "on run argv",
    "set target to item 1 of argv",
    "set theText to item 2 of argv",
    "tell application \"Messages\"",
    "repeat with c in chats",
    "set hit to false",
    "try",
    "if (count of participants of c) is 1 then",
    "set p to item 1 of participants of c",
    "if (full name of p is target) or (name of p is target) or (handle of p is target) then set hit to true",
    "else if name of c is target then",
    "set hit to true",
    "end if",
    "end try",
    "if hit then",
    "send theText to c",
    "return \"sent\"",
    "end if",
    "end repeat",
    "end tell",
    "error \"No conversation found for \" & target number 1",
    "end run",
  ]

  /// Full osascript argument vector. `--` stops option parsing so text starting with `-` is data.
  static func arguments(recipient: String, text: String, lines: [String] = scriptLines) -> [String] {
    lines.flatMap { ["-e", $0] } + ["--", recipient, text]
  }

  enum Failure: Error, Equatable { case empty, scriptFailed(String) }

  /// Runs on a background queue; completion is delivered on the main queue.
  static func send(_ text: String, to recipient: String, completion: @escaping (Result<Void, Failure>) -> Void) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !recipient.isEmpty else { return completion(.failure(.empty)) }
    DispatchQueue.global(qos: .userInitiated).async {
      let result = run(arguments: arguments(recipient: recipient, text: trimmed))
      DispatchQueue.main.async { completion(result) }
    }
  }

  static func run(arguments: [String]) -> Result<Void, Failure> {
    switch runCapturing(arguments: arguments) {
    case .success: return .success(())
    case .failure(let failure): return .failure(failure)
    }
  }

  /// Returns stdout. Exposed so tests can verify argument passing with a harmless script.
  static func runCapturing(arguments: [String]) -> Result<String, Failure> {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = arguments
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do { try process.run() } catch { return .failure(.scriptFailed(error.localizedDescription)) }
    process.waitUntilExit()
    let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
      let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      return .failure(.scriptFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    return .success(stdout.trimmingCharacters(in: .newlines))
  }
}
