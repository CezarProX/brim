import CoreGraphics
import Foundation
import Testing

@testable import Brim

@Suite("Recording · cursor track")
struct RecordingCursorTrackTests {
    @Test func clockMapsHostTimeAndSkipsPauses() {
        var clock = RecordingClock()
        #expect(clock.recordingTime(host: 100) == nil)
        clock.begin(at: 100)
        clock.begin(at: 200)  // only the first frame sets the origin
        #expect(clock.recordingTime(host: 101.5) == 1.5)
        clock.pause(at: 102)
        #expect(clock.isPaused)
        #expect(clock.recordingTime(host: 103) == nil)
        clock.resume(at: 105)
        #expect(!clock.isPaused)
        #expect(clock.pausedDuration(before: 106) == 3)
        #expect(clock.recordingTime(host: 106) == 3)
        #expect(clock.clampedRecordingTime(host: 99) == 0)
        #expect(clock.clampedRecordingTime(host: 104) == 2)
    }

    @Test func builderNormalisesAlignsAndPairsClicks() {
        var clock = RecordingClock()
        clock.begin(at: 10)
        let rect = CGRect(x: 100, y: 50, width: 200, height: 100)
        let events: [RawPointerEvent] = [
            RawPointerEvent(host: 9.5, x: 150, y: 75, kind: .move),  // before the first frame
            RawPointerEvent(host: 11, x: 200, y: 100, kind: .move),
            RawPointerEvent(host: 11.2, x: 200, y: 100, kind: .down(0)),
            RawPointerEvent(host: 11.4, x: 210, y: 100, kind: .up(0)),
        ]
        let track = CursorTrackBuilder.build(events: events, clock: clock, captureRect: rect)
        #expect(track.samples.first == CursorSample(t: 0, x: 0.25, y: 0.25))
        #expect(track.samples[1] == CursorSample(t: 1, x: 0.5, y: 0.5))
        #expect(track.clicks.count == 1)
        let click = track.clicks[0]
        #expect(abs(click.t - 1.2) < 1e-9)
        #expect(abs((click.up ?? 0) - 1.4) < 1e-9)
        #expect(click.x == 0.5 && click.y == 0.5)
    }

    @Test func builderDropsEventsDuringPause() {
        var clock = RecordingClock()
        clock.begin(at: 0)
        clock.pause(at: 1)
        clock.resume(at: 3)
        let events = [RawPointerEvent(host: 2, x: 10, y: 10, kind: .move), RawPointerEvent(host: 4, x: 20, y: 20, kind: .move)]
        let track = CursorTrackBuilder.build(events: events, clock: clock, captureRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(track.samples.map(\.t) == [2])
    }

    @Test func interpolatesAndHoldsEnds() {
        let track = CursorTrack(samples: [CursorSample(t: 1, x: 0, y: 0), CursorSample(t: 2, x: 1, y: 0.5)], clicks: [])
        #expect(track.position(at: 0) == CGPoint(x: 0, y: 0))
        #expect(track.position(at: 1.5) == CGPoint(x: 0.5, y: 0.25))
        #expect(track.position(at: 9) == CGPoint(x: 1, y: 0.5))
        #expect(CursorTrack.empty.position(at: 1) == nil)
        #expect(track.shifted(by: -1).samples.first?.t == 0)
    }

    @Test func smoothingReducesJitterKeepsRestingPointAndTiming() {
        var samples: [CursorSample] = []
        for i in 0...240 {
            let t = Double(i) / 120
            let jitter = (i % 2 == 0 ? 0.01 : -0.01)
            samples.append(CursorSample(t: t, x: 0.5 + (t < 1 ? jitter : 0), y: 0.5))
        }
        let track = CursorTrack(samples: samples, clicks: [])
        let smooth = SmoothedCursorPath(track: track, smoothing: 0.6)
        let raw = SmoothedCursorPath(track: track, smoothing: 0)
        let rawDeviation = abs((raw.position(at: 0.5)?.x ?? 0.5) - 0.5)
        let smoothDeviation = abs((smooth.position(at: 0.5)?.x ?? 0.5) - 0.5)
        #expect(smoothDeviation < rawDeviation / 4)
        // At rest the smoothed pointer is exactly where the user left it.
        #expect(abs((smooth.position(at: 1.9)?.x ?? 0) - 0.5) < 1e-6)
        // A linear move has no lag in the middle (centred filter).
        let ramp = CursorTrack(samples: (0...120).map { CursorSample(t: Double($0) / 60, x: Double($0) / 120, y: 0) }, clicks: [])
        let rampSmooth = SmoothedCursorPath(track: ramp, smoothing: 0.5)
        #expect(abs((rampSmooth.position(at: 1)?.x ?? 0) - 0.5) < 0.002)
    }

    @Test func idlePointerFadesOutAndBackInBeforeMoving() {
        let samples = [CursorSample(t: 0, x: 0.1, y: 0.1), CursorSample(t: 0.5, x: 0.2, y: 0.2), CursorSample(t: 6, x: 0.3, y: 0.3)]
        let visibility = CursorVisibility(track: CursorTrack(samples: samples, clicks: []), idleDelay: 1.5)
        #expect(visibility.opacity(at: 1) == 1)
        #expect(visibility.opacity(at: 3) == 0)
        #expect(visibility.opacity(at: 5.95) > 0.5)  // back before the move at 6 s
        #expect(visibility.opacity(at: 6.2) == 1)
    }

    @Test func clickEffectsPressAndRipple() {
        let click = CursorClick(t: 1, x: 0.5, y: 0.5, button: 0, up: 1.2)
        #expect(ClickEffect.pointerScale(at: 0.5, clicks: [click]) == 1)
        #expect(abs(ClickEffect.pointerScale(at: 1.1, clicks: [click]) - ClickEffect.pressedScale) < 1e-9)
        #expect(ClickEffect.pointerScale(at: 2, clicks: [click]) == 1)
        #expect(ClickEffect.ripples(at: 1.2, clicks: [click]).count == 1)
        #expect(ClickEffect.ripples(at: 2, clicks: [click]).isEmpty)
    }
}

@Suite("Recording · auto zoom")
struct RecordingZoomTests {
    private func click(_ t: Double, _ x: Double = 0.7, _ y: Double = 0.3) -> CursorClick {
        CursorClick(t: t, x: x, y: y, button: 0, up: t + 0.1)
    }

    @Test func burstsOfClicksBecomeOneSegment() {
        let segments = AutoZoomGenerator.segments(clicks: [click(2), click(2.6), click(3.5), click(12)], duration: 20)
        #expect(segments.count == 2)
        #expect(abs(segments[0].start - 1.2) < 1e-9)
        #expect(abs(segments[0].end - 5.1) < 1e-9)
        #expect(segments.allSatisfy { $0.isAuto && $0.scale == 1.8 && $0.focus == .cursor })
    }

    @Test func segmentsStayInsideTheRecordingAndRespectMinimumLength() {
        let segments = AutoZoomGenerator.segments(clicks: [click(0.1), click(9.9)], duration: 10)
        #expect(segments.count == 2)
        #expect(segments[0].start == 0)
        #expect(segments[1].end == 10)
        #expect(segments.allSatisfy { $0.duration >= AutoZoomOptions().minimumDuration - 1e-9 })
        #expect(AutoZoomGenerator.segments(clicks: [click(30)], duration: 10).isEmpty)
        #expect(AutoZoomGenerator.segments(clicks: [click(2, 3, 3)], duration: 10).isEmpty)  // off the captured area
    }

    @Test func regeneratingKeepsManualSegments() {
        let manual = ZoomSegment(start: 1, end: 3, scale: 2.5)
        let generated = [ZoomSegment(start: 2, end: 4, scale: 1.8, isAuto: true), ZoomSegment(start: 6, end: 8, scale: 1.8, isAuto: true)]
        let merged = AutoZoomGenerator.merged(manual: [manual, ZoomSegment(start: 9, end: 10, scale: 2, isAuto: true)], generated: generated)
        #expect(merged.map(\.start) == [1, 6])
    }

    @Test func cameraEasesInHoldsAndReturns() {
        let segment = ZoomSegment(start: 1, end: 4, scale: 2, focus: .fixed(x: 0.8, y: 0.2))
        let path = ZoomCameraPath(segments: [segment], duration: 6) { _ in nil }
        #expect(path.state(at: 0.5) == .identity)
        let early = path.state(at: 1.1).scale
        #expect(early > 1 && early < 1.5)
        let held = path.state(at: 3.5)
        #expect(abs(held.scale - 2) < 0.01)
        // Focus at (0.8, 0.2) is clamped so the visible region stays inside the frame.
        #expect(abs(held.center.x - 0.75) < 0.01 && abs(held.center.y - 0.25) < 0.01)
        #expect(abs(path.state(at: 5.9).scale - 1) < 0.01)
    }

    @Test func instantSegmentsCutStraightIn() {
        let segment = ZoomSegment(start: 1, end: 2, scale: 3, focus: .fixed(x: 0.5, y: 0.5), instant: true)
        let path = ZoomCameraPath(segments: [segment], duration: 3) { _ in nil }
        #expect(abs(path.state(at: 1.01).scale - 3) < 1e-6)
        #expect(abs(path.state(at: 2.05).scale - 1) < 1e-6)
    }

    @Test func followingCameraTracksThePointerWithADeadZone() {
        let segment = ZoomSegment(start: 0, end: 10, scale: 2, focus: .cursor)
        let path = ZoomCameraPath(segments: [segment], duration: 10) { t in CGPoint(x: t < 5 ? 0.4 : 0.6, y: 0.5) }
        let settled = path.state(at: 4.5).center
        #expect(abs(settled.x - 0.4) < 0.01)
        // A 0.2 move with a 0.1375 reach re-aims only by the excess.
        let moved = path.state(at: 9.5).center
        #expect(moved.x > 0.45 && moved.x < 0.47)
    }

    @Test func visibleRectAndClamp() {
        let camera = CameraState(scale: 2, center: CameraState.clampedCenter(CGPoint(x: 0, y: 1), scale: 2))
        #expect(camera.visibleRect == CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
    }
}

@Suite("Recording · timeline")
struct RecordingTimelineTests {
    @Test func identityMapping() {
        let timeline = EditTimeline(sourceDuration: 10)
        #expect(timeline.duration == 10)
        #expect(timeline.sourceTime(forOutput: 3) == 3)
        #expect(timeline.outputTime(forSource: 7) == 7)
    }

    @Test func splitDeleteAndSpeedMapTime() throws {
        var timeline = EditTimeline(sourceDuration: 10)
        let first = timeline.split(atOutput: 4)
        let sliver = timeline.split(atOutput: 4.05)  // would leave a sliver
        #expect(first && !sliver)
        #expect(timeline.clips.count == 2)
        let second = timeline.split(atOutput: 6)
        #expect(second)
        // Clips: [0,4] [4,6] [6,10]; delete the middle.
        let middle = timeline.clips[1].id
        let deleted = timeline.delete(clip: middle)
        #expect(deleted)
        #expect(timeline.duration == 8)
        #expect(timeline.sourceTime(forOutput: 5) == 7)
        #expect(timeline.outputTime(forSource: 5) == nil)
        // Speed the last clip up 2×: its 4 s become 2 s.
        let last = try #require(timeline.clips.last?.id)
        timeline.setSpeed(2, clip: last)
        #expect(timeline.duration == 6)
        #expect(timeline.sourceTime(forOutput: 5) == 8)
        #expect(timeline.outputTime(forSource: 8) == 5)
        #expect(timeline.outputRanges(forSource: 3, 8) == [3...4, 4...5])
        timeline.setSpeed(100, clip: last)
        #expect(timeline.clips.last?.speed == 4)
    }

    @Test func lastClipCannotBeDeleted() throws {
        var timeline = EditTimeline(sourceDuration: 5)
        let id = try #require(timeline.clips.first?.id)
        let deleted = timeline.delete(clip: id)
        #expect(!deleted)
    }

    @Test func trimHandlesRespectNeighbours() throws {
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.split(atOutput: 5)
        let first = try #require(timeline.clips.first?.id), second = timeline.clips[1].id
        timeline.trimStart(clip: first, toSource: 1)
        timeline.trimEnd(clip: first, toSource: 8)  // can't run into the next clip
        #expect(timeline.clips[0].sourceStart == 1 && timeline.clips[0].sourceEnd == 5)
        timeline.trimStart(clip: second, toSource: 2)  // nor back over the previous one
        #expect(timeline.clips[1].sourceStart == 5)
        timeline.trimEnd(clip: second, toSource: 5)
        #expect(abs(timeline.clips[1].sourceEnd - 5.1) < 1e-9)
        #expect(abs(timeline.duration - 4.1) < 1e-9)
        #expect(timeline.sourceTime(forOutput: 0) == 1)
    }

    @Test func historyUndoesAndRedoes() {
        var history = EditHistory<Int>(limit: 3)
        var value = 0
        for next in 1...5 { history.record(value); value = next }
        #expect(history.undoStack == [2, 3, 4])
        value = history.undo(current: value) ?? value
        #expect(value == 4)
        value = history.redo(current: value) ?? value
        #expect(value == 5)
        history.record(value); value = 6
        #expect(!history.canRedo)
    }
}
