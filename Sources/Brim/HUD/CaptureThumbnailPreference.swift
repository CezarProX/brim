import Foundation

/// "Hide the macOS capture thumbnail": the floating preview after a screenshot is controlled by the
/// `com.apple.screencaptureui show-thumbnail` default. screencaptureui reads it at launch, so the
/// change applies the next time that process restarts (log out, or `killall screencaptureui`).
enum CaptureThumbnailPreference {
    static let domain = "com.apple.screencaptureui"
    static let key = "show-thumbnail"

    static func writeArguments(hidden: Bool) -> [String] { ["write", domain, key, "-bool", hidden ? "false" : "true"] }
    static var readArguments: [String] { ["read", domain, key] }

    /// `defaults read` prints 0/1; a missing key means the default (thumbnail shown).
    static func isHidden(readOutput: String?) -> Bool {
        readOutput?.trimmingCharacters(in: .whitespacesAndNewlines) == "0"
    }

    static func currentlyHidden() -> Bool {
        isHidden(readOutput: run(readArguments))
    }

    @discardableResult
    static func setHidden(_ hidden: Bool) -> Bool {
        run(writeArguments(hidden: hidden)) != nil
    }

    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
