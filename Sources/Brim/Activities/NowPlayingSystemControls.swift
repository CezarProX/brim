import AppKit
import Darwin

/// Sends to the active macOS media session, like Control Center and the media keys.
/// MediaRemote is private: resolve it at runtime and fail explicitly if unavailable.
enum NowPlayingSystemControls {
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool
    private static let sendCommand: SendCommand? = {
        guard let library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY | RTLD_LOCAL) else {
            return nil
        }
        guard let symbol = dlsym(library, "MRMediaRemoteSendCommand") else {
            dlclose(library)
            return nil
        }
        // Retain the system framework for the lifetime of the function pointer.
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    private typealias SetElapsedTime = @convention(c) (Double) -> Void
    private static let setElapsedTime: SetElapsedTime? = {
        guard let library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY | RTLD_LOCAL) else {
            return nil
        }
        guard let symbol = dlsym(library, "MRMediaRemoteSetElapsedTime") else {
            dlclose(library)
            return nil
        }
        return unsafeBitCast(symbol, to: SetElapsedTime.self)
    }()

    static func commandCode(_ command: NowPlayingCommand, wasPlaying: Bool) -> Int32? {
        switch command {
        case .playPause: return wasPlaying ? 1 : 0
        case .next: return 4
        case .previous: return 5
        case .seek, .setFavorite, .setShuffle, .setRepeat: return nil
        }
    }

    static func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot,
                        token: NowPlayingActionToken,
                        read: () throws -> NowPlayingSnapshot? = { try NowPlayingAccessibility.snapshot() },
                        send: (Int32) throws -> Bool = send,
                        setPosition: (Double) throws -> Void = setPosition,
                        wait: () async throws -> Void = { try await Task.sleep(for: .milliseconds(120)) }) async throws {
        guard token.isValid else { throw CancellationError() }
        guard let current = try read(), current.source == expected.source,
              current.title == expected.title, current.artist == expected.artist else {
            throw NowPlayingFailure.unavailable("The song changed. Try the control again.")
        }
        if case .playPause = command, current.isPlaying != expected.isPlaying { return }
        guard token.isValid else { throw CancellationError() }
        if case .seek(let position) = command {
            try validateSeek(position, duration: expected.duration)
            try validateSeek(position, duration: current.duration)
            try setPosition(position)
            for _ in 0..<16 {
                try await wait()
                guard token.isValid else { throw CancellationError() }
                if seekWasApplied(try read(), expected: expected, position: position) { return }
            }
            throw NowPlayingFailure.unavailable("The macOS media session did not update the playback position.")
        }
        guard let code = commandCode(command, wasPlaying: expected.isPlaying), try send(code) else {
            throw NowPlayingFailure.unavailable("macOS did not accept the media command.")
        }
        guard case .playPause = command else { return }
        for _ in 0..<16 {
            try await wait()
            guard token.isValid else { throw CancellationError() }
            if NowPlayingAccessibility.playPauseWasApplied(try read(), expected: expected) { return }
        }
        // An accepted request is not evidence of playback. Never send a second
        // command or fall back to clicking the UI after a potentially delayed success.
        throw NowPlayingFailure.unavailable("The macOS media session did not update YouTube Music playback.")
    }

    static func validateSeek(_ position: Double, duration: Double) throws {
        guard position.isFinite, duration.isFinite, duration > 0, position >= 0, position <= duration else {
            throw NowPlayingFailure.unavailable("This playback position is unavailable.")
        }
    }

    static func seekWasApplied(_ current: NowPlayingSnapshot?, expected: NowPlayingSnapshot, position: Double) -> Bool {
        // An exact-end seek can finish the song before the next metadata sample.
        if position.isFinite, expected.duration > 0, position == expected.duration {
            if current == nil { return true }
            if let current, current.source == expected.source,
               current.title != expected.title || current.artist != expected.artist { return true }
        }
        guard let current else { return false }
        return current.source == expected.source && current.title == expected.title && current.artist == expected.artist
            && current.position.isFinite && position.isFinite && abs(current.position - position) <= 2
    }

    private static func setPosition(_ position: Double) throws {
        guard let setElapsedTime else {
            throw NowPlayingFailure.unavailable("System seeking is unavailable on this macOS version.")
        }
        setElapsedTime(position)
    }

    /// The play key's own call: no target and no options, so macOS routes it to its now-playing app
    /// and keeps its implicit relaunch of the last player. nil when MediaRemote is unavailable.
    /// Sending still works from unentitled processes (checked live on macOS 27); only reads are gated.
    static func sendToSystem(_ command: Int32) -> Bool? {
        sendCommand.map { $0(command, nil) }
    }

    private static func send(_ command: Int32) throws -> Bool {
        guard let sendCommand else {
            throw NowPlayingFailure.unavailable("System media controls are unavailable on this macOS version.")
        }
        let options = ["kMRMediaRemoteOptionDisableImplicitAppLaunchBehaviors": true] as CFDictionary
        return sendCommand(command, options)
    }
}
