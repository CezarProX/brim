import Testing
@testable import Brim

struct SystemMediaControlsTests {
    private func track(playing: Bool, title: String = "Song") -> NowPlayingSnapshot {
        NowPlayingSnapshot(source: .youtubeApp, title: title, artist: "Artist", album: "",
                           duration: 100, position: 10, isPlaying: playing)
    }

    @Test func usesExplicitSystemPlayAndPauseInsteadOfToggle() {
        #expect(NowPlayingSystemControls.commandCode(.playPause, wasPlaying: false) == 0)
        #expect(NowPlayingSystemControls.commandCode(.playPause, wasPlaying: true) == 1)
        #expect(NowPlayingSystemControls.commandCode(.next, wasPlaying: true) == 4)
        #expect(NowPlayingSystemControls.commandCode(.previous, wasPlaying: false) == 5)
    }

    @Test func delayedPlaybackSendsOneCommand() async throws {
        var reads = 0
        var commands: [Int32] = []
        try await NowPlayingSystemControls.perform(.playPause, expected: track(playing: false),
            token: NowPlayingActionToken(), read: {
                reads += 1
                return track(playing: reads >= 4)
            }, send: { commands.append($0); return true }, wait: {})
        #expect(commands == [0])
        #expect(reads == 4)
    }

    @Test func alreadyPlayingDoesNotPauseAgainFromStaleMetadata() async throws {
        var commands: [Int32] = []
        try await NowPlayingSystemControls.perform(.playPause, expected: track(playing: false),
            token: NowPlayingActionToken(), read: { track(playing: true) },
            send: { commands.append($0); return true }, wait: {})
        #expect(commands.isEmpty)
    }

    @Test func changedSongDoesNotSend() async {
        var commands: [Int32] = []
        do {
            try await NowPlayingSystemControls.perform(.playPause, expected: track(playing: false),
                token: NowPlayingActionToken(), read: { track(playing: false, title: "Different") },
                send: { commands.append($0); return true }, wait: {})
            Issue.record("Changed song must reject the command")
        } catch { #expect(commands.isEmpty) }
    }

    @Test func invalidTokenDoesNotSend() async {
        let token = NowPlayingActionToken()
        token.invalidate()
        var commands: [Int32] = []
        do {
            try await NowPlayingSystemControls.perform(.playPause, expected: track(playing: false), token: token,
                read: { track(playing: false) }, send: { commands.append($0); return true }, wait: {})
            Issue.record("Invalid token must cancel the command")
        } catch { #expect(commands.isEmpty) }
    }

    @Test func unchangedPlaybackFailsWithoutSendingAgain() async {
        var commands: [Int32] = []
        do {
            try await NowPlayingSystemControls.perform(.playPause, expected: track(playing: false),
                token: NowPlayingActionToken(), read: { track(playing: false) },
                send: { commands.append($0); return true }, wait: {})
            Issue.record("An accepted command must not be mistaken for confirmed playback")
        } catch { #expect(commands == [0]) }
    }
}
