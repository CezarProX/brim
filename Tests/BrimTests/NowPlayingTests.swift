import AppKit
import Combine
import Testing
@testable import Brim

struct NowPlayingTests {
    @Test func browserMetadataPreservesSeparatorsAndUnicode() throws {
        let json = #"{"title":"A | B\n\"C\" 🎵","artist":"Artist","album":"Album","position":90,"duration":180,"isPlaying":true,"artworkURL":"https://lh3.googleusercontent.com/art"}"#
        let track = try NowPlayingSnapshot.browserJSON(json, source: .youtubeChrome)
        #expect(track?.title == "A | B\n\"C\" 🎵")
        #expect(track?.duration == 180)
        #expect(track?.isPlaying == true)
    }

    @Test func invalidOrStoppedBrowserMetadataClearsTrack() throws {
        #expect(try NowPlayingSnapshot.browserJSON("null", source: .youtubeChrome) == nil)
        #expect(try NowPlayingSnapshot.browserJSON(#"{"title":"","artist":"","album":"","position":0,"duration":0,"isPlaying":false}"#, source: .youtubeChrome) == nil)
    }

    @Test func sanitizesTimingWithoutTouchingMetadata() {
        let track = NowPlayingSnapshot(source: .music, title: "Track", artist: "", album: "", duration: 10, position: 500, isPlaying: true)
        #expect(track.position == 10)
        #expect(NowPlayingSnapshot(source: .music, title: "T", artist: "", album: "", duration: .infinity, position: .nan, isPlaying: false).position == 0)
    }

    @Test func artworkNetworkBoundaryAllowsOnlyKnownHTTPSHosts() {
        #expect(NowPlayingSnapshot.safeArtworkURL("https://i.scdn.co/image/abc") != nil)
        #expect(NowPlayingSnapshot.safeArtworkURL("https://lh3.googleusercontent.com/x") != nil)
        for url in ["http://i.scdn.co/x", "https://i.scdn.co.evil.test/x", "file:///tmp/art.png", "https://127.0.0.1/x", "https://user@i.scdn.co/x"] {
            #expect(NowPlayingSnapshot.safeArtworkURL(url) == nil)
        }
    }

    @Test func browserScriptGuardsExactOriginAndHasNoExternalFetch() {
        #expect(NowPlayingBrowser.script(for: nil).contains("location.hostname !== 'music.youtube.com'"))
        #expect(!NowPlayingBrowser.script(for: nil).contains("fetch("))
        #expect(NowPlayingBrowser.script(for: .next).contains("next-button"))
    }

    @Test func appleEventObjectSpecifierUsesTypedCodes() {
        let spec = NowPlayingAppleEvents.property("pTrk")
        #expect(spec.descriptorType == NowPlayingAppleEvents.code("obj "))
        #expect(spec.forKeyword(NowPlayingAppleEvents.code("seld"))?.typeCodeValue == NowPlayingAppleEvents.code("pTrk"))
    }
}

actor StubNowPlayingProvider: NowPlayingProviding {
    var values: [NowPlayingSource: NowPlayingSnapshot] = [:]
    var denied = false
    var reads = 0
    var connections = 0
    var commandFails = false
    var discoveredSources: [NowPlayingSource] = []
    func runningSources() async -> [NowPlayingSource] { discoveredSources }
    func setRunningSources(_ sources: [NowPlayingSource]) { discoveredSources = sources }
    private var suspendNextRead = false
    private var pendingRead: CheckedContinuation<Void, Never>?
    private var suspensionObserver: CheckedContinuation<Void, Never>?
    func connect(_ source: NowPlayingSource) async throws { connections += 1 }
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
        reads += 1
        if suspendNextRead {
            suspendNextRead = false
            await withCheckedContinuation { continuation in
                pendingRead = continuation
                suspensionObserver?.resume()
                suspensionObserver = nil
            }
        }
        if denied { throw NowPlayingFailure.permission(source.name) }
        return values[source]
    }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {
        guard token.isValid else { throw CancellationError() }
        if commandFails { throw NowPlayingFailure.unavailable("The player rejected this control.") }
    }
    func set(_ snapshots: [NowPlayingSnapshot]) { values = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.source, $0) }) }
    func deny() { denied = true }
    func setCommandFailure(_ value: Bool) { commandFails = value }
    func suspendNext() { suspendNextRead = true }
    func waitForSuspendedRead() async {
        guard pendingRead == nil else { return }
        await withCheckedContinuation { suspensionObserver = $0 }
    }
    func resumeRead() { pendingRead?.resume(); pendingRead = nil }
}

@MainActor
struct NowPlayingModelTests {
    private func snapshot(_ source: NowPlayingSource, playing: Bool) -> NowPlayingSnapshot {
        NowPlayingSnapshot(source: source, title: source.name, artist: "Artist", album: "Album", duration: 180, position: 40, isPlaying: playing)
    }

    @Test func pausedMusicStaysInIslandForTenMinutesLikeIOS() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snapshot(.music, playing: true)])
        let start = Date()
        var now = start
        let model = NowPlayingModel(provider: provider, enabledSources: [.music], artworkNow: { now })
        await model.refreshNow()
        #expect(model.isInIsland(now: now))
        now = start.addingTimeInterval(5)
        await provider.set([snapshot(.music, playing: false)])
        await model.refreshNow()
        #expect(model.isInIsland(now: now.addingTimeInterval(9 * 60)))
        #expect(!model.isInIsland(now: now.addingTimeInterval(10 * 60 + 1)))
        await provider.set([snapshot(.music, playing: true)])
        await model.refreshNow()
        #expect(model.isInIsland(now: now.addingTimeInterval(60 * 60)))
        await provider.set([])
        await model.refreshNow()
        await model.refreshNow()
        #expect(!model.isInIsland(now: now))
    }

    @Test func songFoundAlreadyPausedDoesNotClaimIsland() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snapshot(.music, playing: false)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.music])
        await model.refreshNow()
        #expect(model.track != nil)
        #expect(!model.isInIsland())
    }

    @Test func unchangedPollingDoesNotInvalidateNotch() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snapshot(.music, playing: false)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.music])
        await model.refreshNow()
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        await model.refreshNow()
        #expect(publications == 0)
        withExtendedLifetime(subscription) {}
    }

    @Test func repeatedPermissionFailureDoesNotInvalidateNotch() async {
        let provider = StubNowPlayingProvider()
        await provider.deny()
        let model = NowPlayingModel(provider: provider, enabledSources: [.music])
        await model.refreshNow()
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        await model.refreshNow()
        #expect(publications == 0)
        #expect(model.accessSource == .music)
        withExtendedLifetime(subscription) {}
    }

    @Test func repeatedIdlePollingDoesNotInvalidateNotch() async {
        let provider = StubNowPlayingProvider()
        let model = NowPlayingModel(provider: provider)
        await model.refreshNow()
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        await model.refreshNow()
        #expect(publications == 0)
        withExtendedLifetime(subscription) {}
    }

    @Test func advancingPlaybackStillPublishesProgress() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snapshot(.music, playing: true)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.music])
        await model.refreshNow()
        let advanced = NowPlayingSnapshot(source: .music, title: NowPlayingSource.music.name,
            artist: "Artist", album: "Album", duration: 180, position: 43, isPlaying: true)
        await provider.set([advanced])
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        await model.refreshNow()
        #expect(model.track?.position == 43)
        #expect(publications == 1)
        withExtendedLifetime(subscription) {}
    }

    @Test func embeddedArtworkLoadsAsynchronouslyWithoutReplacingNewerTrack() async throws {
        let provider = StubNowPlayingProvider()
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let withArtwork = NowPlayingSnapshot(source: .music, title: "First", artist: "Artist", album: "Album",
            duration: 180, position: 40, isPlaying: false, artworkData: png)
        await provider.set([withArtwork])
        let model = NowPlayingModel(provider: provider, enabledSources: [.music])
        await model.refreshNow()
        // Metadata is available immediately; bounded polling observes the background decode completion.
        for _ in 0..<100 where model.track?.artwork == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.track?.artwork != nil)
        #expect(model.track?.title == "First")

        let second = NowPlayingSnapshot(source: .music, title: "Second", artist: "Artist", album: "Album",
            duration: 180, position: 0, isPlaying: false, artworkData: png)
        await provider.set([second])
        await model.refreshNow()
        // Disconnect in the same main-actor turn, before the newly scheduled artwork task can publish.
        model.disconnect(.music)
        try await Task.sleep(for: .milliseconds(30))
        #expect(model.track == nil)
    }

    @Test func disconnectedModelNeverPollsOrPrompts() async {
        let provider = StubNowPlayingProvider()
        let model = NowPlayingModel(provider: provider)
        await model.refreshNow()
        #expect(await provider.reads == 0)
        #expect(await provider.connections == 0)
        #expect(model.track == nil)
    }

    @Test func playingTrackWinsAndStoppingClearsStaleMetadata() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snapshot(.music, playing: false), snapshot(.spotify, playing: true)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.music, .spotify])
        await model.refreshNow()
        #expect(model.track?.snapshot.source == .spotify)
        #expect(await provider.connections == 0)
        await provider.set([])
        await model.refreshNow()
        // One empty read can be a hiccup between songs: the player stays until a second one agrees.
        #expect(model.track?.snapshot.source == .spotify)
        await model.refreshNow()
        #expect(model.track == nil)
        #expect(model.status.contains("Nothing playing"))
        await provider.set([snapshot(.music, playing: true)])
        await model.refreshNow()
        await provider.set([])
        await model.refreshNow()
        #expect(model.track != nil, "a song in between restarts the count")
    }

    @Test func permissionRevocationClearsTrackAndExplainsNextStep() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snapshot(.music, playing: true)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.music])
        await model.refreshNow()
        #expect(model.track != nil)
        await provider.deny()
        await model.refreshNow()
        #expect(model.track == nil)
        #expect(model.status.contains("Automation"))
    }

    @Test func disconnectClearsCurrentSourceAndPersistsChoice() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snapshot(.music, playing: true)])
        var saved: [NowPlayingSource] = [.music]
        let model = NowPlayingModel(provider: provider, enabledSources: [.music], persist: { saved = $0 })
        await model.refreshNow()
        model.disconnect(.music)
        #expect(model.track == nil)
        #expect(!model.isConnected)
        #expect(saved.isEmpty)
    }

    @Test func invalidatedActionTokenCannotAuthorizeQueuedAction() {
        let token = NowPlayingActionToken()
        #expect(token.isValid)
        token.invalidate()
        #expect(!token.isValid)
    }

    @Test func slowPollingKeepsControlsAvailableAndNeverOverlaps() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snapshot(.music, playing: false), snapshot(.spotify, playing: true)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.music, .spotify])
        await model.refreshNow()
        await provider.suspendNext()
        let polling = Task { await model.refreshNow() }
        await provider.waitForSuspendedRead()
        #expect(model.track != nil)
        #expect(!model.isBusy)
        await model.refreshNow()
        #expect(await provider.reads == 3)
        // Starting a connection invalidates the poll, so it cannot queue the remaining player reads.
        model.connect(.youtubeChrome)
        await provider.resumeRead()
        await polling.value
        #expect(await provider.reads == 3)
    }

    @Test func automaticDiscoveryReadsPlayingAppWithoutAnyConnectSelection() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snapshot(.youtubeApp, playing: true)])
        await provider.setRunningSources([.youtubeApp])
        let model = NowPlayingModel(provider: provider)
        await model.refreshNow()
        #expect(model.track?.snapshot.source == .youtubeApp)
        #expect(model.track?.isPlaying == true)
        #expect(await provider.connections == 0)
        await provider.setRunningSources([])
        await model.refreshNow()
        #expect(model.track == nil)
    }

    @Test func commandFailureSurvivesSuccessfulPollingUntilRetry() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snapshot(.youtubeApp, playing: false)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.youtubeApp])
        await model.refreshNow()
        await provider.setCommandFailure(true)
        await model.command(.playPause)?.value
        #expect(model.commandError == "The player rejected this control.")
        await model.refreshNow()
        #expect(model.status == "The player rejected this control.")
        #expect(model.commandError != nil)
        await provider.setCommandFailure(false)
        await model.command(.playPause)?.value
        #expect(model.commandError == nil)
        #expect(model.status.isEmpty)
    }

    @Test func changingTracksClearsErrorForPreviousTrack() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snapshot(.youtubeApp, playing: false)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.youtubeApp])
        await model.refreshNow()
        await provider.setCommandFailure(true)
        await model.command(.playPause)?.value
        await provider.set([NowPlayingSnapshot(source: .youtubeApp, title: "Different song", artist: "Artist",
                                             album: "Album", duration: 180, position: 0, isPlaying: true)])
        await model.refreshNow()
        #expect(model.commandError == nil)
        #expect(model.status.isEmpty)
    }
}

struct YouTubeMusicAccessibilityTests {
    @Test func scopedPlayerClickStaysInsideVerifiedWindow() {
        let window = CGRect(x: 100, y: 50, width: 600, height: 400)
        #expect(NowPlayingAccessibility.scopedClickPoint(
            button: CGRect(x: 300, y: 380, width: 32, height: 32), window: window) == CGPoint(x: 316, y: 396))
        #expect(NowPlayingAccessibility.scopedClickPoint(
            button: CGRect(x: 750, y: 380, width: 32, height: 32), window: window) == nil)
        #expect(NowPlayingAccessibility.scopedClickPoint(
            button: CGRect(x: 300, y: 380, width: 600, height: 100), window: window) == nil)
    }

    @Test func rewrappedPlayerWindowKeepsItsVerifiedIdentity() {
        let frame = CGRect(x: 100, y: 50, width: 600, height: 400)
        #expect(NowPlayingAccessibility.sameWindowIdentity(
            selectedPID: 101, candidatePID: 101, selectedTitle: "YouTube Music - Song",
            candidateTitle: "YouTube Music - Song", selectedFrame: frame, candidateFrame: frame))
        #expect(!NowPlayingAccessibility.sameWindowIdentity(
            selectedPID: 101, candidatePID: 102, selectedTitle: "YouTube Music - Song",
            candidateTitle: "YouTube Music - Song", selectedFrame: frame, candidateFrame: frame))
        #expect(!NowPlayingAccessibility.sameWindowIdentity(
            selectedPID: 101, candidatePID: 101, selectedTitle: "YouTube Music - Song",
            candidateTitle: "YouTube Music - Another", selectedFrame: frame, candidateFrame: frame))
        #expect(!NowPlayingAccessibility.sameWindowIdentity(
            selectedPID: 101, candidatePID: 101, selectedTitle: "YouTube Music - Song",
            candidateTitle: "YouTube Music - Song", selectedFrame: frame,
            candidateFrame: frame.offsetBy(dx: 60, dy: 0)))
    }

    @Test func webAreaURLAcceptsChromiumStringAndFoundationURL() {
        let page = "https://music.youtube.com/watch?v=5KRM9707tyA&list=RDAMVMx7hRCB7YoQ8"
        #expect(NowPlayingAccessibility.urlString(page) == page)
        #expect(NowPlayingAccessibility.urlString(URL(string: page)!) == page)
    }

    @Test func currentPlayerToolbarUsesArtistTextAndWatchThumbnail() throws {
        typealias Text = NowPlayingAccessibility.PlayerText
        let nodes = [Text(role: "AXButton", label: "Înapoi"),
            Text(role: "AXButton", label: "Întrerupe"),
            Text(role: "AXButton", label: "Înainte"),
            Text(role: "AXStaticText", label: "0:46 / 2:46"),
            Text(role: "AXHeading", label: "Cachalma"),
            Text(role: "AXStaticText", label: "Cachalma"),
            Text(role: "AXStaticText", label: "Mario, Lazy Ed și Efra"),
            Text(role: "AXLink", label: "Album", url: "https://music.youtube.com/browse/MPREb_example")]
        let track = try #require(NowPlayingAccessibility.snapshot(from: nodes,
            pageURL: "https://music.youtube.com/watch?v=5KRM9707tyA&list=RDAMVMx7hRCB7YoQ8"))
        #expect(track.artist == "Mario, Lazy Ed și Efra")
        #expect(track.artworkURL == "https://i.ytimg.com/vi/5KRM9707tyA/maxresdefault.jpg")
    }

    @Test func verifiesDelayedPlaybackWithoutSendingAnotherToggle() async throws {
        let before = NowPlayingSnapshot(source: .youtubeApp, title: "Song", artist: "Artist", album: "",
                                        duration: 100, position: 10, isPlaying: false)
        let after = NowPlayingSnapshot(source: .youtubeApp, title: "Song", artist: "Artist", album: "",
                                       duration: 100, position: 10, isPlaying: true)
        var presses = 0
        var reads = 0
        try await NowPlayingAccessibility.pressAndVerify(.playPause, token: NowPlayingActionToken(), press: {
            presses += 1
            return before
        }, read: {
            reads += 1
            return reads < 4 ? before : after
        }, wait: {})
        #expect(presses == 1)
        #expect(reads == 4)
    }

    @Test func unchangedPlaybackFailsWithoutRetoggling() async {
        let before = NowPlayingSnapshot(source: .youtubeApp, title: "Song", artist: "Artist", album: "",
                                        duration: 100, position: 10, isPlaying: false)
        var presses = 0
        do {
            try await NowPlayingAccessibility.pressAndVerify(.playPause, token: NowPlayingActionToken(), press: {
                presses += 1
                return before
            }, read: { before }, wait: {})
            Issue.record("An accepted AX action is not proof that playback changed")
        } catch {
            #expect(presses == 1)
        }
    }

    @Test func cancelledPlaybackDoesNotPress() async {
        let token = NowPlayingActionToken()
        token.invalidate()
        var presses = 0
        do {
            try await NowPlayingAccessibility.pressAndVerify(.playPause, token: token, press: {
                presses += 1
                return NowPlayingSnapshot(source: .youtubeApp, title: "Song", artist: "Artist", album: "",
                                          duration: 100, position: 10, isPlaying: false)
            }, read: { nil }, wait: {})
            Issue.record("An invalid token must cancel playback")
        } catch { #expect(presses == 0) }
    }

    @Test func scopedPlayerActivationRejectsWrongOrUnverifiedTarget() {
        func allowed(ownerPID: pid_t = 101, expectedPID: pid_t = 101, running: Bool = true,
                     focused: Bool = true, enabled: Bool = true, valid: Bool = true, member: Bool = true) -> Bool {
            NowPlayingAccessibility.permitsScopedActivation(windowPID: ownerPID, expectedPID: expectedPID, isWindowMember: member,
                isRunning: running, isFocused: focused, isEnabled: enabled, tokenIsValid: valid)
        }
        #expect(allowed())
        #expect(!allowed(ownerPID: 0, expectedPID: 0))
        #expect(!allowed(ownerPID: -1, expectedPID: -1))
        #expect(!allowed(ownerPID: 102))
        #expect(!allowed(running: false))
        #expect(!allowed(focused: false))
        #expect(!allowed(enabled: false))
        #expect(!allowed(valid: false))
        #expect(!allowed(member: false))
    }

    @Test func focusRestorationNeverOverridesAnotherForegroundApplication() {
        #expect(NowPlayingAccessibility.shouldRestoreForeground(previousPID: 100, playerPID: 101, currentPID: 101))
        #expect(!NowPlayingAccessibility.shouldRestoreForeground(previousPID: 100, playerPID: 101, currentPID: 102))
        #expect(!NowPlayingAccessibility.shouldRestoreForeground(previousPID: 101, playerPID: 101, currentPID: 101))
        #expect(!NowPlayingAccessibility.shouldRestoreForeground(previousPID: nil, playerPID: 101, currentPID: 101))
        #expect(!NowPlayingAccessibility.shouldRestoreForeground(previousPID: 0, playerPID: 101, currentPID: 101))
        #expect(!NowPlayingAccessibility.shouldRestoreForeground(previousPID: 100, playerPID: 101, currentPID: nil))
    }

    @Test func playPauseReadbackRequiresSameSongAndChangedPlaybackState() {
        func snapshot(source: NowPlayingSource = .youtubeApp, title: String = "Song", artist: String = "Artist",
                      playing: Bool, position: Double = 10) -> NowPlayingSnapshot {
            NowPlayingSnapshot(source: source, title: title, artist: artist, album: "Album", duration: 100,
                               position: position, isPlaying: playing)
        }
        let paused = snapshot(playing: false)
        #expect(NowPlayingAccessibility.playPauseWasApplied(snapshot(playing: true), expected: paused))
        #expect(NowPlayingAccessibility.playPauseWasApplied(paused, expected: snapshot(playing: true)))
        #expect(!NowPlayingAccessibility.playPauseWasApplied(snapshot(playing: false, position: 11), expected: paused))
        #expect(!NowPlayingAccessibility.playPauseWasApplied(snapshot(title: "Next song", playing: true), expected: paused))
        #expect(!NowPlayingAccessibility.playPauseWasApplied(snapshot(artist: "Other artist", playing: true), expected: paused))
        #expect(!NowPlayingAccessibility.playPauseWasApplied(snapshot(source: .music, playing: true), expected: paused))
        #expect(!NowPlayingAccessibility.playPauseWasApplied(nil, expected: paused))
    }

    /// YouTube Music's September 2026 player bar, as Brim read it on macOS 27: no named toolbar,
    /// no heading, the title inside "Now playing" and artist/album as buttons.
    @Test func redesignedPlayerBarStillNamesTheSong() {
        typealias Text = NowPlayingAccessibility.PlayerText
        let nodes = [Text(role: "AXGroup", label: ""), Text(role: "AXSlider", label: "Glisor"),
            Text(role: "AXGroup", label: "Now playing"), Text(role: "AXStaticText", label: "Ghici Cine?"),
            Text(role: "AXButton", label: "Guess Who"), Text(role: "AXStaticText", label: " • "),
            Text(role: "AXButton", label: "Tot Ce Audio Vol. I"), Text(role: "AXStaticText", label: " • 2026"),
            Text(role: "AXGroup", label: "PLAYBACK_CONTROLS"), Text(role: "AXCheckBox", label: "Redă aleatoriu"),
            Text(role: "AXButton", label: "Înapoi"), Text(role: "AXButton", label: "Redă"),
            Text(role: "AXButton", label: "Înainte"), Text(role: "AXCheckBox", label: "Repetare dezactivată"),
            Text(role: "AXStaticText", label: "1:55 / 2:51"), Text(role: "AXGroup", label: "ACTION_BAR"),
            Text(role: "AXCheckBox", label: "apreciază videoclipul"), Text(role: "AXButton", label: "MORE")]
        let track = NowPlayingAccessibility.snapshot(from: nodes)
        #expect(track?.title == "Ghici Cine?")
        #expect(track?.artist == "Guess Who")
        #expect(track?.album == "Tot Ce Audio Vol. I")
        #expect(track?.position == 115)
        #expect(track?.duration == 171)
        #expect(track?.isPlaying == false)
    }

    /// Found on Home, the player's document must still be cached so its watch page is read later.
    @Test func playerPageIsKeptBeforeASongPageOpens() {
        #expect(NowPlayingAccessibility.playingPageIndex(["https://music.youtube.com/"]) == 0)
        #expect(NowPlayingAccessibility.playingPageIndex(
            ["https://music.youtube.com/", "https://music.youtube.com/watch?v=5KRM9707tyA"]) == 1)
        #expect(NowPlayingAccessibility.playingPageIndex(["https://accounts.google.com/"]) == nil)
    }

    @Test func redesignedBarWithSeveralArtistsJoinsThem() {
        typealias Text = NowPlayingAccessibility.PlayerText
        let nodes = [Text(role: "AXGroup", label: "Now playing"), Text(role: "AXStaticText", label: "Cachalma"),
            Text(role: "AXButton", label: "Mario"), Text(role: "AXStaticText", label: ", "),
            Text(role: "AXButton", label: "Lazy Ed"), Text(role: "AXStaticText", label: " și "),
            Text(role: "AXButton", label: "Efra"), Text(role: "AXStaticText", label: " • "),
            Text(role: "AXButton", label: "Cachalma"), Text(role: "AXGroup", label: "PLAYBACK_CONTROLS"),
            Text(role: "AXButton", label: "Înapoi"), Text(role: "AXButton", label: "Întrerupe"),
            Text(role: "AXButton", label: "Înainte"), Text(role: "AXStaticText", label: "0:12 / 2:46")]
        let track = NowPlayingAccessibility.snapshot(from: nodes)
        #expect(track?.artist == "Mario · Lazy Ed · Efra")
        #expect(track?.isPlaying == true)
    }

    @Test func romanianLiveToolbarExtractsHeadingArtistsAndProgress() {
        typealias Text = NowPlayingAccessibility.PlayerText
        let nodes = [Text(role: "AXToolbar", label: "Bara playerului"),
            Text(role: "AXButton", label: "Înapoi"), Text(role: "AXButton", label: "Întrerupe"),
            Text(role: "AXButton", label: "Înainte"), Text(role: "AXStaticText", label: "2:11 /3:39"),
            Text(role: "AXHeading", label: "Euforia"), Text(role: "AXStaticText", label: "Euforia"),
            Text(role: "AXLink", label: "Calinacho", url: "https://music.youtube.com/channel/one"),
            Text(role: "AXLink", label: "Mario Fresh", url: "https://music.youtube.com/channel/two"),
            Text(role: "AXLink", label: "Ai Grijă", url: "https://music.youtube.com/browse/MPREb_liveAlbum")]
        let track = NowPlayingAccessibility.snapshot(from: nodes)
        #expect(track?.title == "Euforia")
        #expect(track?.artist == "Calinacho · Mario Fresh")
        #expect(track?.isPlaying == true)
        #expect(track?.position == 131)
        #expect(track?.duration == 219)
        #expect(track?.album == "Ai Grijă")
        #expect(track?.albumURL == "https://music.youtube.com/browse/MPREb_liveAlbum")
    }

    @Test func recommendationTextWithoutPlayerHeadingCannotBecomeSong() {
        typealias Text = NowPlayingAccessibility.PlayerText
        let nodes = [Text(role: "AXButton", label: "Înapoi"), Text(role: "AXButton", label: "Redă"),
            Text(role: "AXButton", label: "Înainte"), Text(role: "AXStaticText", label: "Recommendation")]
        #expect(NowPlayingAccessibility.snapshot(from: nodes) == nil)
    }
}

struct NowPlayingAlbumArtworkTests {
    @Test func actualAlbumMetadataResolvesCoverOnlyWhenTitleMatches() {
        let html = #"<html><head><meta property="og:title" content="Kiss Land (Deluxe)"><meta property="og:image" content="https://yt3.googleusercontent.com/real-album-art=w544-h544"></head></html>"#
        #expect(NowPlayingAlbumArtwork.imageURL(html: html, expectedAlbum: "Kiss Land (Deluxe)")?.host == "yt3.googleusercontent.com")
        #expect(NowPlayingAlbumArtwork.imageURL(html: html, expectedAlbum: "Different album") == nil)
    }

    @Test func albumURLRejectsArbitraryPagesAndStripsTrackingQuery() {
        #expect(NowPlayingSnapshot.safeAlbumURL("https://music.youtube.com/browse/MPREb_actual?si=tracking")?.absoluteString == "https://music.youtube.com/browse/MPREb_actual")
        for value in ["https://example.com/browse/MPREb_actual", "http://music.youtube.com/browse/MPREb_actual", "https://music.youtube.com/search?q=Track", "https://music.youtube.com/browse/MPREb_actual/../../account", "https://user@music.youtube.com/browse/MPREb_actual"] {
            #expect(NowPlayingSnapshot.safeAlbumURL(value) == nil)
        }
    }

    @Test func parserHandlesAttributeOrderEntitiesAndRejectsGenericLogo() {
        let html = #"<META content='Rock &amp; Roll &#39;24' property='og:title'><meta content='https://lh3.googleusercontent.com/art?a=1&amp;b=2' property='og:image'>"#
        #expect(NowPlayingAlbumArtwork.imageURL(html: html, expectedAlbum: "Rock & Roll '24")?.query == "a=1&b=2")
        let generic = #"<meta property="og:title" content="Kiss Land (Deluxe)"><meta property="og:image" content="https://www.gstatic.com/youtube/logo.png">"#
        #expect(NowPlayingAlbumArtwork.imageURL(html: generic, expectedAlbum: "Kiss Land (Deluxe)") == nil)
    }

    @Test func consentRedirectMustReturnToExactRequestedAlbum() throws {
        let album = try #require(URL(string: "https://music.youtube.com/browse/MPREb_actual"))
        let legitimate = try #require(URL(string: "https://consent.youtube.com/m?continue=https%3A%2F%2Fmusic.youtube.com%2Fbrowse%2FMPREb_actual%3Fcbrd%3D1"))
        let unrelated = try #require(URL(string: "https://consent.youtube.com/m?continue=https%3A%2F%2Fmusic.youtube.com%2Fbrowse%2FMPREb_other"))
        #expect(NowPlayingAlbumArtwork.permitsRedirect(legitimate, requestedAlbum: album))
        #expect(!NowPlayingAlbumArtwork.permitsRedirect(unrelated, requestedAlbum: album))
    }
}

@MainActor
struct ArtworkRetryTests {
    @Test func failedArtworkRetriesAfterCooldownAndStopsAfterSuccess() async throws {
        let provider = StubNowPlayingProvider()
        let snapshot = NowPlayingSnapshot(source: .music, title: "Song", artist: "Artist", album: "Album",
            duration: 100, position: 0, isPlaying: true, artworkURL: "https://i.scdn.co/image/test")
        await provider.set([snapshot])
        var now = Date()
        var attempts = 0
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let model = NowPlayingModel(provider: provider, enabledSources: [.music], artworkLoader: { _ in
            attempts += 1
            return attempts == 1 ? nil : png
        }, artworkNow: { now })
        await model.refreshNow()
        try await Task.sleep(for: .milliseconds(50))
        #expect(attempts == 1)
        #expect(model.track?.artwork == nil)
        await model.refreshNow()
        #expect(attempts == 1)
        now = now.addingTimeInterval(31)
        await model.refreshNow()
        for _ in 0..<100 where model.track?.artwork == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(attempts == 2)
        #expect(model.track?.artwork != nil)
        now = now.addingTimeInterval(60)
        await model.refreshNow()
        #expect(attempts == 2)
        model.stop()
    }
}
