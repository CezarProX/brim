import Foundation

/// Sends a transport command to one app's player like Control Center: through mediaremoted,
/// without activating the app. Since macOS 15.4 mediaremoted ignores unentitled processes, so
/// the bundled helper runs inside Apple-signed /usr/bin/perl (Resources/MediaRemoteHelper).
enum NowPlayingMediaRemote {
    struct Helper: Equatable {
        let script: URL
        let library: URL
    }

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private static let timeout: TimeInterval = 5

    static var helper: Helper? {
        helper(in: Bundle.main.resourceURL) { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// Only files inside the signed app bundle; a development build without them has no helper.
    static func helper(in resources: URL?, exists: (URL) -> Bool) -> Helper? {
        guard let resources else { return nil }
        let helper = Helper(script: resources.appendingPathComponent("brim-mediaremote.pl"),
                            library: resources.appendingPathComponent("BrimMediaRemote.dylib"))
        return exists(helper.script) && exists(helper.library) && exists(perl) ? helper : nil
    }

    /// `send` for `NowPlayingSystemControls.perform`, aimed at `bundleID`'s player only.
    static func send(_ command: Int32, to bundleID: String) throws -> Bool {
        guard let helper else { throw NowPlayingFailure.unavailable("Media controls are unavailable in this build.") }
        return try accepted(run(helper, command: command, bundleID: bundleID))
    }

    /// The shared long-lived helper, when this build bundles one.
    static let stream: MediaRemoteStreamClient? = helper.map(MediaRemoteStreamClient.init)

    /// Like `send`, but through the running stream helper when there is one (no process launch).
    static func sendFast(_ command: Int32, to bundleID: String) async throws -> Bool {
        if let stream, stream.isRunning, let line = await stream.send(command: command, bundleID: bundleID) {
            return try accepted(line)
        }
        return try await Task.detached(priority: .userInitiated) { try send(command, to: bundleID) }.value
    }

    /// The helper's stand-in for "no particular app" (`BrimMediaRemote.m`, `kQSSystemTarget`).
    static let systemTarget = "*"

    /// What the Mac's play key does: one MediaRemote command to the system, which resumes its
    /// now-playing app in place (or relaunches the last one). The running helper first, then the
    /// same call in-process, then a one-shot helper.
    static func sendToSystem(_ command: Int32) async throws -> Bool {
        if let stream, stream.isRunning, let line = await stream.send(command: command, bundleID: systemTarget) {
            return try accepted(line)
        }
        if NowPlayingSystemControls.sendToSystem(command) == true { return true }
        guard helper != nil else { throw NowPlayingFailure.unavailable("macOS did not accept the media command.") }
        return try await Task.detached(priority: .userInitiated) { try send(command, to: systemTarget) }.value
    }

    /// The target app has a player, but macOS isn't treating it as now playing. A command aimed at
    /// it would land on the app that is (a film in a browser), so the helper refuses to send it.
    struct NotNowPlaying: LocalizedError {
        var errorDescription: String? { "Another app is playing right now. Start the song in its player to control it here." }
    }

    /// Interprets the helper's single output line.
    static func accepted(_ output: String) throws -> Bool {
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if line == "notnowplaying" { throw NotNowPlaying() }
        if line == "notfound" {
            throw NowPlayingFailure.unavailable("macOS doesn’t list this player right now. Start playback in the app and try again.")
        }
        let parts = line.split(separator: " ")
        guard parts.count == 2, parts[0] == "sent", let error = Int(parts[1]) else {
            throw NowPlayingFailure.unavailable("macOS did not accept the media command.")
        }
        return error == 0
    }

    private static func run(_ helper: Helper, command: Int32, bundleID: String) throws -> String {
        let process = Process()
        process.executableURL = perl
        process.arguments = [helper.script.path, helper.library.path]
        process.environment = ["QS_MR_BUNDLE": bundleID, "QS_MR_COMMAND": String(command)]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw NowPlayingFailure.timeout
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data.prefix(256), as: UTF8.self)
    }
}
