import AppKit
import Carbon
import os

/// Public Apple Events only. PID targeting cannot launch an application that quits mid-poll.
/// Every request has a timeout, and consent is checked without prompting before polling.
struct NowPlayingAppleEvents {
    let source: NowPlayingSource
    let target: NSAppleEventDescriptor
    let deadline: Date
    let actionToken: NowPlayingActionToken?

    init(source: NowPlayingSource, askPermission: Bool = false, actionToken: NowPlayingActionToken? = nil) throws {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).first,
              !app.isTerminated else { throw NowPlayingFailure.notRunning(source.name) }
        self.source = source
        self.actionToken = actionToken
        target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
        deadline = Date().addingTimeInterval(2.5)
        let pid = app.processIdentifier
        let allowed: Bool
        if !askPermission, let cached = Self.consent.withLock({ $0[pid] }), Date().timeIntervalSince(cached.checked) < 30 {
            allowed = cached.allowed
        } else {
            allowed = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, askPermission) == noErr
            Self.consent.withLock { $0[pid] = (allowed, Date()) }
        }
        guard allowed else { throw NowPlayingFailure.permission(source.name) }
    }

    /// Consent checks round-trip to tccd and block for ~50ms; a poll reuses the answer for 30s.
    /// An explicit Enable access request always asks again.
    private static let musicCover = OSAllocatedUnfairLock<(key: String, data: Data)?>(initialState: nil)
    private static let consent = OSAllocatedUnfairLock(initialState: [pid_t: (allowed: Bool, checked: Date)]())

    static func code(_ value: String) -> OSType {
        precondition(value.utf8.count == 4)
        return value.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }

    static func property(_ name: String, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        object(want: "prop", form: "prop", selector: NSAppleEventDescriptor(typeCode: code(name)), container: container)
    }

    static func object(want: String, form: String = "indx", selector: NSAppleEventDescriptor,
                       container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(want)), forKeyword: code("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(selector, forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        // A record with these four fields is a valid object specifier.
        return record.coerce(toDescriptorType: code("obj ")) ?? record
    }

    func get(_ object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try send(eventClass: "core", eventID: "getd", parameters: ["----": object])
    }

    func send(eventClass: String, eventID: String,
              parameters: [String: NSAppleEventDescriptor] = [:]) throws -> NSAppleEventDescriptor {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw NowPlayingFailure.timeout }
        guard actionToken?.isValid != false else { throw CancellationError() }
        let event = NSAppleEventDescriptor(eventClass: Self.code(eventClass), eventID: Self.code(eventID),
            targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        for (key, value) in parameters { event.setParam(value, forKeyword: Self.code(key)) }
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: min(0.7, remaining))
            if let error = reply.paramDescriptor(forKeyword: Self.code("errn")), error.int32Value != 0 {
                if error.int32Value == -1743 || error.int32Value == -1744 { throw NowPlayingFailure.permission(source.name) }
                if error.int32Value == -1712 { throw NowPlayingFailure.timeout }
                throw NowPlayingFailure.unavailable(source.isBrowser
                    ? "In \(source == .youtubeChrome ? "Chrome → View → Developer" : "Safari → Develop"), enable Allow JavaScript from Apple Events."
                    : "\(source.name) could not read this track. Try another song.")
            }
            return reply.paramDescriptor(forKeyword: Self.code("----")) ?? .null()
        } catch let failure as NowPlayingFailure { throw failure }
        catch { throw NowPlayingFailure.unavailable("\(source.name) is unavailable or did not respond.") }
    }

    func nativeSnapshot() throws -> NowPlayingSnapshot? {
        let state = try get(Self.property("pPlS")).enumCodeValue
        guard state != Self.code("kPSS") else { return nil }
        let track = Self.property("pTrk")
        let properties = try get(Self.property("pALL", of: track))
        func field(_ key: String) -> NSAppleEventDescriptor? { properties.forKeyword(Self.code(key)) }
        guard let title = field("pnam")?.stringValue, !title.isEmpty else { return nil }
        let position = try get(Self.property("pPos")).doubleValue
        // Spotify's desktop scripting implementation returns milliseconds, despite its sdef prose.
        let duration = (field("pDur")?.doubleValue ?? 0) / (source == .spotify ? 1000 : 1)
        var data: Data?
        if source == .music {
            // The cover is megabytes of Apple Event payload; fetch it once per song, not once per poll.
            let key = [title, field("pArt")?.stringValue ?? "", field("pAlb")?.stringValue ?? ""].joined(separator: "\u{0}")
            if let cached = Self.musicCover.withLock({ $0?.key == key ? $0?.data : nil }) {
                data = cached
            } else {
                let artwork = Self.object(want: "cArt", selector: NSAppleEventDescriptor(int32: 1), container: track)
                if let descriptor = try? get(Self.property("pRaw", of: artwork)), descriptor.data.count > 0,
                   descriptor.data.count <= 5_000_000 {
                    let bytes = descriptor.data
                    data = bytes
                    Self.musicCover.withLock { $0 = (key, bytes) }
                }
            }
        }
        let shuffle = try? get(Self.property(source == .music ? "pShE" : "pShu")).booleanValue
        var snapshot = NowPlayingSnapshot(source: source, title: title, artist: field("pArt")?.stringValue ?? "",
            album: field("pAlb")?.stringValue ?? "", duration: duration, position: position,
            isPlaying: state == Self.code("kPSP"), artworkData: data, artworkURL: field("aUrl")?.stringValue,
            isFavorite: source == .music ? field("pLov")?.booleanValue : nil, isShuffling: shuffle)
        if source == .spotify {
            snapshot.pageURL = [field("spur")?.stringValue, field("ID  ")?.stringValue]
                .compactMap { $0 }.compactMap { NowPlayingNavigation.safeTrackURL($0, source: source)?.absoluteString }.first
        }
        snapshot.repeatMode = readRepeat()
        return snapshot
    }

    /// Music: `song repeat` (pRpt, off/one/all). Spotify: boolean `repeating` (pRep).
    private func readRepeat() -> RepeatMode? {
        if source == .music {
            guard let value = try? get(Self.property("pRpt")),
                  let text = Self.codeString(value.enumCodeValue) else { return nil }
            return RepeatMode(musicCode: text)
        }
        guard let value = try? get(Self.property("pRep")) else { return nil }
        return RepeatMode(spotifyRepeating: value.booleanValue)
    }

    static func codeString(_ code: OSType) -> String? {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii)
    }

    /// Apple Music or Spotify: play or pause (not toggle), wherever macOS routes media keys.
    func transport(play: Bool) throws {
        _ = try send(eventClass: source == .music ? "hook" : "spfy", eventID: play ? "Play" : "Paus")
    }

    func nativeCommand(_ command: NowPlayingCommand) throws {
        let eventID: String
        switch command {
        case .playPause: eventID = "PlPs"
        case .next: eventID = "Next"
        case .previous: eventID = "Prev"
        case .seek(let position):
            _ = try send(eventClass: "core", eventID: "setd", parameters: [
                "----": Self.property("pPos"), "data": NSAppleEventDescriptor(double: position)
            ])
            return
        case .setFavorite(let favorite):
            guard source == .music else { throw NowPlayingFailure.unavailable("\(source.name) has no favorites control.") }
            _ = try send(eventClass: "core", eventID: "setd", parameters: [
                "----": Self.property("pLov", of: Self.property("pTrk")),
                "data": NSAppleEventDescriptor(boolean: favorite)
            ])
            return
        case .setShuffle(let shuffle):
            _ = try send(eventClass: "core", eventID: "setd", parameters: [
                "----": Self.property(source == .music ? "pShE" : "pShu"),
                "data": NSAppleEventDescriptor(boolean: shuffle)
            ])
            return
        case .setRepeat(let mode):
            let value = source == .music
                ? NSAppleEventDescriptor(enumCode: Self.code(mode.musicCode))
                : NSAppleEventDescriptor(boolean: mode.spotifyRepeating)
            _ = try send(eventClass: "core", eventID: "setd", parameters: [
                "----": Self.property(source == .music ? "pRpt" : "pRep"), "data": value
            ])
            return
        }
        _ = try send(eventClass: source == .music ? "hook" : "spfy", eventID: eventID)
    }
}

actor NowPlayingProvider: NowPlayingProviding {

    func runningSources() async -> [NowPlayingSource] {
        let priority: [NowPlayingSource] = [.youtubeApp, .music, .spotify, .youtubeChrome, .youtubeSafari]
        return priority.filter { source in
            NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).contains { !$0.isTerminated }
        }
    }

    func connect(_ source: NowPlayingSource) async throws {
        if source == .youtubeApp {
            guard NowPlayingAccessibility.isTrusted else {
                throw NowPlayingFailure.accessibility
            }
        } else { _ = try NowPlayingAppleEvents(source: source, askPermission: true) }
    }

    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
        if source == .youtubeApp {
            guard let snapshot = try NowPlayingAccessibility.snapshot() else { return nil }
            // Off a watch page the app's tree carries no cover; the page's Media Session does.
            guard snapshot.artworkURL == nil else { return snapshot }
            return snapshot.withArtworkURL(await YouTubeAppArtwork.url(for: snapshot.title))
        }
        let bridge = try NowPlayingAppleEvents(source: source)
        return source.isBrowser ? try NowPlayingBrowser.snapshot(bridge) : try bridge.nativeSnapshot()
    }

    /// Controls are fire-and-forget: the UI already flipped optimistically, so nothing here
    /// reads the player back first or polls afterwards; the next sample reconciles.
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {
        guard token.isValid else { throw CancellationError() }
        let source = expected.source
        if source == .youtubeApp { try await performOnYouTubeApp(command, expected: expected, token: token); return }
        let bridge = try NowPlayingAppleEvents(source: source, actionToken: token)
        if source.isBrowser { try NowPlayingBrowser.perform(command, expected: expected, bridge: bridge); return }
        if case .seek(let position) = command {
            try NowPlayingSystemControls.validateSeek(position, duration: expected.duration)
        }
        try bridge.nativeCommand(command)
    }

    /// Next/Previous go to the page first: the accessibility press checks the song against the app's
    /// tree, which can lag a whole track behind and then refuses (seen live). The page's own check
    /// uses its Media Session. Without page scripting, the accessibility press remains.
    private func pressOnYouTubeApp(_ command: NowPlayingCommand, expected: NowPlayingSnapshot,
                                   token: NowPlayingActionToken) async throws {
        switch command {
        case .next, .previous:
            do {
                try await YouTubeMusicQueueReader.pressTransport(command, expected: expected)
                return
            } catch {
                guard token.isValid else { throw CancellationError() }
                Logger(subsystem: "io.github.cezarprox.brim", category: "controls")
                    .error("page \(String(describing: command), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        default:
            break
        }
        try await NowPlayingAccessibility.perform(command, expected: expected, token: token)
    }

    private func performOnYouTubeApp(_ command: NowPlayingCommand, expected: NowPlayingSnapshot,
                                     token: NowPlayingActionToken) async throws {
        let bundle = expected.source.bundleID
        switch command {
        case .playPause, .next, .previous:
            if NowPlayingMediaRemote.helper != nil, let code = NowPlayingSystemControls.commandCode(command, wasPlaying: expected.isPlaying) {
                // Like Control Center: straight to YouTube Music's player, without bringing its window forward.
                // macOS only routes that while YouTube Music is its now-playing app; otherwise press the
                // player's own button, or the command would reach whatever else plays (a film in Arc).
                do {
                    guard try await NowPlayingMediaRemote.sendFast(code, to: bundle) else {
                        throw NowPlayingFailure.unavailable("macOS did not accept the media command.")
                    }
                } catch is NowPlayingMediaRemote.NotNowPlaying {
                    try await pressOnYouTubeApp(command, expected: expected, token: token)
                }
            } else {
                // Development builds lack the bundled helper; clicking the player needs its window in front.
                try await pressOnYouTubeApp(command, expected: expected, token: token)
            }
        case .seek(let position):
            try NowPlayingSystemControls.validateSeek(position, duration: expected.duration)
            if let stream = NowPlayingMediaRemote.stream {
                // The new time goes to macOS's now-playing app, so the helper sets it only while that is
                // YouTube Music; never fall back to an untargeted seek that could move a film in Arc.
                guard stream.isRunning, let line = await stream.seek(to: position, bundleID: bundle) else {
                    throw NowPlayingFailure.unavailable("Seeking is unavailable right now. Try again in a moment.")
                }
                guard try NowPlayingMediaRemote.accepted(line) else {
                    throw NowPlayingFailure.unavailable("macOS did not accept the new position.")
                }
                return
            }
            // Development builds lack the bundled helper.
            try await NowPlayingSystemControls.perform(command, expected: expected, token: token)
        case .setFavorite, .setShuffle, .setRepeat:
            throw NowPlayingFailure.unavailable("YouTube Music doesn’t expose this control.")
        }
    }
}
