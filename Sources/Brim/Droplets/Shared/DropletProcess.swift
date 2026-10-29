import Foundation

/// Runs a short-lived command without a shell, so arguments can never be interpreted as code.
enum DropletProcess {
  struct Result: Sendable {
    let status: Int32
    let output: String
  }

  static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 30) async -> Result? {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
          continuation.resume(returning: nil)
          return
        }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        continuation.resume(
          returning: Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self)))
      }
    }
  }
}
