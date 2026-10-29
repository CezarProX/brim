import AppKit
import os

/// Play with no song on screen (Home's idle card, Recently Played), done the way the Mac's own play
/// key and Control Center do it: one MediaRemote command to the system,
/// which resumes whatever last played (Music, Spotify, a YouTube Music tab) in place. Nothing is
/// launched, focused, opened at a URL or clicked unless macOS itself would do it.
@MainActor
enum NowPlayingIdlePlay {
    /// MRCommand numbers (kMRPlay, kMRPause).
    static let play: Int32 = 0
    static let pause: Int32 = 1

    enum Step: Equatable, Sendable {
        /// MRMediaRemoteSendCommand with no target and no options: the play key itself.
        case system
        /// The same command aimed at the last player's own MediaRemote session, if that app still runs.
        case player(bundleID: String)
        /// Nothing ever played here: open Music in the background, as macOS does for the play key.
        case openMusic
    }

    enum Outcome: Equatable, Sendable {
        case started(Step)
        case failed(String)
    }

    /// The side effects, injectable so tests never touch the user's player.
    struct Actions {
        /// Untargeted MediaRemote command; true when macOS accepted it.
        var sendToSystem: (Int32) async throws -> Bool
        /// MediaRemote command aimed at one app's player (never UI scripting).
        var sendToPlayer: (Int32, String) async throws -> Bool
        /// Waits briefly for a playing song to show up; false when none did.
        var confirmPlayback: () async -> Bool
        var isRunning: (String) -> Bool
        var openMusic: () -> Bool
    }

    private static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "controls")

    /// Fallback order. Each later step runs only after the earlier ones demonstrably failed: the
    /// command was refused, or it was accepted but no song started playing. A last player that is
    /// still running gets the command itself: the system command goes to whatever macOS calls now
    /// playing, which can be a film in a browser rather than the music on screen.
    static func steps(lastPlayed: NowPlayingSource?, running: Bool = false) -> [Step] {
        guard let lastPlayed else { return [.system, .openMusic] }
        return running ? [.player(bundleID: lastPlayed.bundleID)] : [.system]
    }

    /// The running app a press should go to, or nil for the system.
    static func runningPlayer(lastPlayed: NowPlayingSource?, actions: Actions) -> String? {
        guard let bundleID = lastPlayed?.bundleID, actions.isRunning(bundleID) else { return nil }
        return bundleID
    }

    /// Apple Music and Spotify take play and pause straight from Apple Events, so they still answer
    /// while macOS routes media commands to another app. The YouTube Music players have no such path.
    static func directSource(forBundle bundleID: String) -> NowPlayingSource? {
        [NowPlayingSource.music, .spotify].first { $0.bundleID == bundleID }
    }

    /// A command aimed at one player: through MediaRemote while it is now playing, otherwise directly
    /// when the player allows it. Never through whatever else macOS calls now playing.
    static func sendToPlayer(_ command: Int32, bundleID: String) async throws -> Bool {
        do {
            return try await NowPlayingMediaRemote.sendFast(command, to: bundleID)
        } catch let refused as NowPlayingMediaRemote.NotNowPlaying {
            guard let source = directSource(forBundle: bundleID) else { throw refused }
            let isPlay = command == play
            try await Task.detached(priority: .userInitiated) {
                try NowPlayingAppleEvents(source: source).transport(play: isPlay)
            }.value
            return true
        }
    }

    static func run(lastPlayed: NowPlayingSource?, actions: Actions) async -> Outcome {
        var failure = "macOS did not accept the media command."
        let running = runningPlayer(lastPlayed: lastPlayed, actions: actions) != nil
        for step in steps(lastPlayed: lastPlayed, running: running) {
            do {
                if try await attempt(step, actions: actions) { return .started(step) }
            } catch is CancellationError {
                return .failed(failure)
            } catch {
                log.error("idle play \(String(describing: step), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                failure = error.localizedDescription
            }
        }
        return .failed(failure)
    }

    private static func attempt(_ step: Step, actions: Actions) async throws -> Bool {
        switch step {
        case .system:
            guard try await actions.sendToSystem(play) else { return false }
            return await actions.confirmPlayback()
        case .player(let bundleID):
            guard actions.isRunning(bundleID), try await actions.sendToPlayer(play, bundleID) else { return false }
            return await actions.confirmPlayback()
        case .openMusic:
            // Opening Music is the result: it may have nothing queued, exactly like the play key.
            return actions.openMusic()
        }
    }

    /// Production wiring; `confirmPlayback` watches `model` for a playing song.
    static func live(for model: NowPlayingModel) -> Actions {
        Actions(
            sendToSystem: { try await NowPlayingMediaRemote.sendToSystem($0) },
            sendToPlayer: { try await sendToPlayer($0, bundleID: $1) },
            confirmPlayback: { [weak model] in await model?.waitForPlayback(timeout: 1.5) ?? false },
            isRunning: { bundleID in
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
            },
            openMusic: {
                guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: NowPlayingSource.music.bundleID)
                else { return false }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                NSWorkspace.shared.openApplication(at: app, configuration: configuration)
                return true
            })
    }
}
