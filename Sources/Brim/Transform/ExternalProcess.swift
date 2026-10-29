import Foundation

/// Runs a command-line tool to completion, killing it if the task is cancelled.
enum ExternalProcess {
  static func run(_ tool: String, _ arguments: [String], failure: String = "The tool failed.") throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try process.run()
    // Drain stderr while the tool runs so a chatty tool can't fill the pipe and stall.
    let collected = LockedData()
    errors.fileHandleForReading.readabilityHandler = { handle in collected.append(handle.availableData) }
    while process.isRunning {
      if Task.isCancelled {
        process.terminate()
        errors.fileHandleForReading.readabilityHandler = nil
        throw TransformError.cancelled
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    errors.fileHandleForReading.readabilityHandler = nil
    collected.append(errors.fileHandleForReading.readDataToEndOfFile())
    guard process.terminationStatus == 0 else {
      let text = String(decoding: collected.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
      throw TransformError.failed(text.isEmpty ? failure : String(text.suffix(160)))
    }
  }

  private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    func append(_ more: Data) { lock.lock(); storage.append(more); lock.unlock() }
    var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
  }
}
