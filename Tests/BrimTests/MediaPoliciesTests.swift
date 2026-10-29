import CoreGraphics
import Foundation
import Testing

@testable import Brim

struct TrackSwipePolicyTests {
  @Test func leftSwipeIsNextAndReverseFlips() {
    #expect(TrackSwipeTracker.direction(forDeltaX: -30, reversed: false) == .next)
    #expect(TrackSwipeTracker.direction(forDeltaX: 30, reversed: false) == .previous)
    #expect(TrackSwipeTracker.direction(forDeltaX: -30, reversed: true) == .previous)
    #expect(TrackSwipeTracker.direction(forDeltaX: 30, reversed: true) == .next)
  }

  @Test func belowThresholdDoesNotFire() {
    var tracker = TrackSwipeTracker()
    tracker.feed(deltaX: -TrackSwipeTracker.threshold + 1, deltaY: 0)
    #expect(tracker.commit(reversed: false) == nil)
  }

  @Test func pastThresholdFiresOnceThenResets() {
    var tracker = TrackSwipeTracker()
    for _ in 0..<10 { tracker.feed(deltaX: -10, deltaY: 1) }
    #expect(tracker.commit(reversed: false) == .next)
    #expect(tracker.commit(reversed: false) == nil)
    #expect(tracker.accumulatedX == 0)
  }

  @Test func mostlyVerticalScrollIsIgnored() {
    var tracker = TrackSwipeTracker()
    tracker.feed(deltaX: -70, deltaY: 90)
    #expect(tracker.commit(reversed: false) == nil)
  }

  @Test func nonFiniteInputIsDropped() {
    var tracker = TrackSwipeTracker()
    tracker.feed(deltaX: .nan, deltaY: 0)
    tracker.feed(deltaX: .infinity, deltaY: 0)
    #expect(tracker.accumulatedX == 0)
  }

  @Test func stretchIsElasticAndBounded() {
    #expect(TrackSwipeTracker.elastic(0) == 0)
    let small = TrackSwipeTracker.elastic(10)
    let large = TrackSwipeTracker.elastic(1_000)
    #expect(small > 0 && small < large)
    #expect(large < TrackSwipeTracker.maxStretch)
    #expect(TrackSwipeTracker.elastic(-10) == -small)
  }
}

struct VisualizerMathTests {
  @Test func springConvergesToTargetWithoutOvershootingBounds() {
    var value: Float = 0, velocity: Float = 0
    for _ in 0..<120 {
      (value, velocity) = VisualizerMath.springStep(value: value, velocity: velocity, target: 0.8, dt: 1.0 / 60)
      #expect(value >= 0 && value <= 1)
    }
    #expect(abs(value - 0.8) < 0.02)
  }

  @Test func springIgnoresBadInput() {
    let result = VisualizerMath.springStep(value: 0.3, velocity: 0, target: .nan, dt: 0.016)
    #expect(result.0 == 0.3)
    let stalled = VisualizerMath.springStep(value: 0, velocity: 0, target: 1, dt: 5)
    #expect(stalled.0 < 0.6)   // a 5 s stall integrates as one 50 ms step
  }

  @Test func normalizeMapsSilenceToZeroAndLoudToOne() {
    #expect(VisualizerMath.normalize(0) == 0)
    #expect(VisualizerMath.normalize(.nan) == 0)
    #expect(VisualizerMath.normalize(5) == 1)
    #expect(VisualizerMath.normalize(0.05) > VisualizerMath.normalize(0.01))
  }
}

struct MarqueePolicyTests {
  @Test func scrollsOnlyWhenTextOverflowsAndEnabled() {
    #expect(MarqueePolicy.needsScroll(textWidth: 300, containerWidth: 200, enabled: true))
    #expect(!MarqueePolicy.needsScroll(textWidth: 200, containerWidth: 200, enabled: true))
    #expect(!MarqueePolicy.needsScroll(textWidth: 300, containerWidth: 200, enabled: false))
    #expect(!MarqueePolicy.needsScroll(textWidth: 300, containerWidth: 0, enabled: true))
    #expect(!MarqueePolicy.needsScroll(textWidth: .nan, containerWidth: 200, enabled: true))
  }

  @Test func offsetHoldsThenGlidesThenRepeats() {
    #expect(MarqueePolicy.offset(at: 0, textWidth: 300) == 0)
    #expect(MarqueePolicy.offset(at: MarqueePolicy.pause - 0.1, textWidth: 300) == 0)
    #expect(MarqueePolicy.offset(at: MarqueePolicy.pause + 1, textWidth: 300) < 0)
    let cycle = MarqueePolicy.pause + MarqueePolicy.loopDuration(textWidth: 300)
    #expect(MarqueePolicy.offset(at: cycle + 0.01, textWidth: 300) == 0)
  }
}

struct CompactTitlePolicyTests {
  @Test func combinesKeepToggles() {
    #expect(CompactTitlePolicy.visibleText(title: "T", artist: "A", keepSong: true, keepArtist: true) == "T · A")
    #expect(CompactTitlePolicy.visibleText(title: "T", artist: "A", keepSong: true, keepArtist: false) == "T")
    #expect(CompactTitlePolicy.visibleText(title: "T", artist: "A", keepSong: false, keepArtist: true) == "A")
    #expect(CompactTitlePolicy.visibleText(title: "T", artist: "A", keepSong: false, keepArtist: false) == nil)
    #expect(CompactTitlePolicy.visibleText(title: "T", artist: "", keepSong: false, keepArtist: true) == nil)
  }
}

struct MediaSettingsTests {
  private func settings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "media-\(UUID().uuidString)")!)
  }

  @Test func defaultsAreOptInForNetworkAndCapture() {
    let s = settings()
    #expect(!s.lyricsEnabled && !s.liveVisualizerEnabled)
    #expect(s.trackSwipeEnabled && s.scrollLongNames && s.notchTrackTitle)
    #expect(s.mediaLeftButtons == [.favorite] && s.mediaRightButtons == [.output])
  }

  @Test func buttonsRoundTripAndCapAtTwo() {
    let s = settings()
    s.mediaRightButtons = [.lyrics, .output, .shuffle]
    #expect(s.mediaRightButtons == [.lyrics, .output])
    s.mediaLeftButtons = []
    #expect(s.mediaLeftButtons.isEmpty)
  }

  @Test func fullscreenPolicyNeedsBothFlags() {
    let s = settings()
    #expect(!MediaIslandPolicy.shouldHideMedia(frontAppIsFullscreen: true, settings: s))
    s.hideMediaInFullscreen = true
    #expect(MediaIslandPolicy.shouldHideMedia(frontAppIsFullscreen: true, settings: s))
    #expect(!MediaIslandPolicy.shouldHideMedia(frontAppIsFullscreen: false, settings: s))
  }
}

struct LiveBarsTests {
  @Test func heightsFollowLevelsAndStayInside() {
    let size = CGSize(width: 23, height: 18)
    let rects = WaveformDrawing.liveBars(in: size, levels: [0, 0.5, 1, .nan, 2, -1])
    #expect(rects.count == 6)
    #expect(rects[0].height < rects[1].height && rects[1].height < rects[2].height)
    #expect(rects.allSatisfy { $0.minX >= 0 && $0.maxX <= size.width && $0.minY >= 0 && $0.maxY <= size.height })
    #expect(rects[3].height == rects[0].height && rects[4].height == rects[2].height)
    #expect(WaveformDrawing.liveBars(in: .zero, levels: [1]).isEmpty)
  }
}
