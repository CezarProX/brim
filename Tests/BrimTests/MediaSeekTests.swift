import Foundation
import Testing
@testable import Brim

struct MediaSeekTests {
    private func track(position: Double = 10, duration: Double = 100, title: String = "Song") -> NowPlayingSnapshot {
        NowPlayingSnapshot(source: .youtubeApp, title: title, artist: "Artist", album: "",
                           duration: duration, position: position, isPlaying: true)
    }

    @Test func exactEndAcceptsCompletionOrNextSongButMidSongDoesNot() {
        #expect(NowPlayingSystemControls.seekWasApplied(nil, expected: track(), position: 100))
        #expect(NowPlayingSystemControls.seekWasApplied(track(position: 0, title: "Next"), expected: track(), position: 100))
        #expect(!NowPlayingSystemControls.seekWasApplied(nil, expected: track(), position: 50))
        #expect(!NowPlayingSystemControls.seekWasApplied(track(position: 0, title: "Next"), expected: track(), position: 50))
    }

    @Test func seekSendsOnceAndWaitsForActualPosition() async throws {
        var reads = 0
        var positions: [Double] = []
        try await NowPlayingSystemControls.perform(.seek(65), expected: track(), token: NowPlayingActionToken(),
            read: { reads += 1; return track(position: reads < 4 ? 10 : 66) },
            send: { _ in Issue.record("Seeking must not send a transport command"); return false },
            setPosition: { positions.append($0) }, wait: {})
        #expect(positions == [65])
        #expect(reads == 4)
    }

    @Test func seekRejectsInvalidPositionsBeforeSending() async {
        for position in [Double.nan, .infinity, -.infinity, -1, 101] {
            var sent = false
            do {
                try await NowPlayingSystemControls.perform(.seek(position), expected: track(), token: NowPlayingActionToken(),
                    read: { track() }, setPosition: { _ in sent = true }, wait: {})
                Issue.record("Invalid seek should fail")
            } catch { #expect(!sent) }
        }
    }

    @Test func seekRejectsUnknownDurationAndChangedTrack() async {
        for current in [track(duration: 0), track(title: "New song")] {
            var sent = false
            do {
                try await NowPlayingSystemControls.perform(.seek(65), expected: track(), token: NowPlayingActionToken(),
                    read: { current }, setPosition: { _ in sent = true }, wait: {})
                Issue.record("Unverified target should fail")
            } catch { #expect(!sent) }
        }
    }

    @Test func seekNeverRetriesWhenReadbackDoesNotConfirm() async {
        var positions: [Double] = []
        do {
            try await NowPlayingSystemControls.perform(.seek(65), expected: track(), token: NowPlayingActionToken(),
                read: { track() }, setPosition: { positions.append($0) }, wait: {})
            Issue.record("Unchanged playback position should fail")
        } catch { #expect(positions == [65]) }
    }

    @Test func seekReadbackCannotConfirmDifferentSongOrInvalidPosition() {
        #expect(NowPlayingSystemControls.seekWasApplied(track(position: 66), expected: track(), position: 65))
        #expect(!NowPlayingSystemControls.seekWasApplied(track(position: 65, title: "Other"), expected: track(), position: 65))
        #expect(!NowPlayingSystemControls.seekWasApplied(track(position: .nan), expected: track(), position: 65))
        #expect(!NowPlayingSystemControls.seekWasApplied(nil, expected: track(), position: 65))
    }

    @Test func cancelledSeekDoesNotReachSetter() async {
        let token = NowPlayingActionToken()
        var sent = false
        do {
            try await NowPlayingSystemControls.perform(.seek(65), expected: track(), token: token,
                read: { token.invalidate(); return track() }, setPosition: { _ in sent = true }, wait: {})
            Issue.record("Cancelled seek should fail")
        } catch { #expect(!sent) }
    }

    @Test func seekAcceptsStartAndEndOfKnownTrack() async throws {
        for position in [0.0, 100.0] {
            var sent: Double?
            try await NowPlayingSystemControls.perform(.seek(position), expected: track(), token: NowPlayingActionToken(),
                read: { track(position: sent ?? 10) }, setPosition: { sent = $0 }, wait: {})
            #expect(sent == position)
        }
    }

    @Test func browserSeekRejectsNonFiniteLiteralAndGuardsLiveDuration() {
        #expect(NowPlayingBrowser.script(for: .seek(.nan)).contains("return 'unavailable'"))
        let script = NowPlayingBrowser.script(for: .seek(65))
        #expect(script.contains("media.currentTime = position"))
        #expect(script.contains("position > media.duration"))
    }
}
