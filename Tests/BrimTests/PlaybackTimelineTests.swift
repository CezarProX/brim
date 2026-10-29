import AppKit
import Testing
@testable import Brim

struct PlaybackTimelineTests {
    @Test func clockAdvancesOnlyWhilePlayingAndStopsAtEnd() {
        let date = Date(timeIntervalSince1970: 100)
        for playing in [true, false] {
            let snapshot = NowPlayingSnapshot(source: .music, title: "T", artist: "A", album: "", duration: 20, position: 18, isPlaying: playing)
            let track = NowPlayingTrack(snapshot: snapshot, artwork: nil, sampledAt: date)
            #expect(track.position(at: date.addingTimeInterval(1)) == (playing ? 19 : 18))
            #expect(track.position(at: date.addingTimeInterval(9)) == (playing ? 20 : 18))
            #expect(track.position(at: date.addingTimeInterval(-2)) == 18)
        }
    }

    @Test func stalledSourceCannotAdvanceIndefinitely() {
        let date = Date(timeIntervalSince1970: 100)
        let snapshot = NowPlayingSnapshot(source: .music, title: "T", artist: "A", album: "", duration: 200, position: 18, isPlaying: true)
        let track = NowPlayingTrack(snapshot: snapshot, artwork: nil, sampledAt: date)
        #expect(track.position(at: date.addingTimeInterval(60)) == 21)
    }

    @Test func seekingMapsLocalCoordinatesAndClampsEdges() {
        #expect(PlaybackTimeline.position(x: 172, width: 344, duration: 200) == 100)
        #expect(PlaybackTimeline.position(x: -20, width: 344, duration: 200) == 0)
        #expect(PlaybackTimeline.position(x: 400, width: 344, duration: 200) == 200)
        #expect(PlaybackTimeline.position(x: .nan, width: 344, duration: 200) == nil)
        #expect(PlaybackTimeline.position(x: 10, width: 0, duration: 200) == nil)
    }
}
