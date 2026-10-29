import CoreGraphics
import Foundation

/// Whether the island should drop its music activity while another app is fullscreen.
/// The shell passes whether the front app is fullscreen; the setting lives in `AppSettings`.
enum MediaIslandPolicy {
  static func shouldHideMedia(frontAppIsFullscreen: Bool, settings: AppSettings = .shared) -> Bool {
    frontAppIsFullscreen && settings.hideMediaInFullscreen
  }
}

enum TrackSwipeDirection: Equatable { case next, previous }

/// Turns a stream of two-finger scroll deltas into an elastic stretch and, once released
/// past the threshold, a next/previous decision.
struct TrackSwipeTracker {
  static let threshold: CGFloat = 56
  static let maxStretch: CGFloat = 14
  private(set) var accumulatedX: CGFloat = 0
  private var accumulatedY: CGFloat = 0
  private var fired = false

  /// Rubber-band stretch for the artwork: grows fast, saturates at `maxStretch`.
  var stretch: CGFloat { Self.elastic(accumulatedX) }

  static func elastic(_ offset: CGFloat) -> CGFloat {
    guard offset.isFinite else { return 0 }
    let magnitude = abs(offset)
    let eased = maxStretch * (1 - 1 / (magnitude / maxStretch * 0.55 + 1))
    return offset < 0 ? -eased : eased
  }

  /// Natural scrolling: fingers moving left (negative delta) mean "next".
  static func direction(forDeltaX x: CGFloat, reversed: Bool) -> TrackSwipeDirection {
    let forward = x < 0
    return forward != reversed ? .next : .previous
  }

  mutating func feed(deltaX: CGFloat, deltaY: CGFloat) {
    guard deltaX.isFinite, deltaY.isFinite, !fired else { return }
    accumulatedX += deltaX
    accumulatedY += deltaY
  }

  /// Fires at most once per gesture, only for clearly horizontal motion past the threshold.
  mutating func commit(reversed: Bool) -> TrackSwipeDirection? {
    defer { reset() }
    guard abs(accumulatedX) >= Self.threshold, abs(accumulatedX) > abs(accumulatedY) * 1.5 else { return nil }
    return Self.direction(forDeltaX: accumulatedX, reversed: reversed)
  }

  mutating func reset() {
    accumulatedX = 0
    accumulatedY = 0
    fired = false
  }
}

/// Pure maths for the live visualizer's bar motion.
enum VisualizerMath {
  /// Critically-damped-ish spring step toward `target`; returns the new (value, velocity).
  static func springStep(value: Float, velocity: Float, target: Float, dt: Float,
                         stiffness: Float = 220, damping: Float = 22) -> (Float, Float) {
    guard dt > 0, dt.isFinite, value.isFinite, velocity.isFinite, target.isFinite else { return (value, velocity) }
    let step = min(dt, 1.0 / 20)   // never integrate across a stall
    let force = stiffness * (target - value) - damping * velocity
    let nextVelocity = velocity + force * step
    let nextValue = min(1, max(0, value + nextVelocity * step))
    return (nextValue, nextVelocity)
  }

  /// Maps RMS-style power into a perceptual 0...1 bar height.
  static func normalize(_ power: Float, floor: Float = 0.002, ceiling: Float = 0.35) -> Float {
    guard power.isFinite, power > floor else { return 0 }
    let unit = min(1, (power - floor) / (ceiling - floor))
    return unit.squareRoot()
  }
}

/// Decides whether a title must scroll, and how fast.
enum MarqueePolicy {
  static let pointsPerSecond: CGFloat = 32
  static let pause: TimeInterval = 1.4
  static let gap: CGFloat = 36

  static func needsScroll(textWidth: CGFloat, containerWidth: CGFloat, enabled: Bool) -> Bool {
    enabled && textWidth.isFinite && containerWidth.isFinite && containerWidth > 0 && textWidth > containerWidth + 0.5
  }

  /// Seconds for one full loop (text plus gap), excluding the pause.
  static func loopDuration(textWidth: CGFloat) -> TimeInterval {
    TimeInterval((textWidth + gap) / pointsPerSecond)
  }

  /// Horizontal offset at `elapsed` seconds: holds, glides one loop, repeats.
  static func offset(at elapsed: TimeInterval, textWidth: CGFloat) -> CGFloat {
    let travel = TimeInterval(textWidth + gap) / TimeInterval(pointsPerSecond)
    let cycle = pause + travel
    let phase = elapsed.truncatingRemainder(dividingBy: cycle)
    guard phase > pause else { return 0 }
    return -CGFloat((phase - pause) / travel) * (textWidth + gap)
  }
}

/// How the compact island shows the song on a notchless display.
enum CompactTitlePolicy {
  /// Text beside the artwork while playing: song, artist or both per the "keep" toggles.
  static func visibleText(title: String, artist: String, keepSong: Bool, keepArtist: Bool) -> String? {
    switch (keepSong, keepArtist) {
    case (true, true): return artist.isEmpty ? title : "\(title) · \(artist)"
    case (true, false): return title
    case (false, true): return artist.isEmpty ? nil : artist
    case (false, false): return nil
    }
  }
}

extension CompactTitlePolicy {
  /// What the compact island prints next to the artwork. A notched Mac shows the song in the
  /// "Notch track title" slot; a notchless island follows the Keep song / Keep artist toggles.
  static func text(hasNotch: Bool, title: String, artist: String, settings: AppSettings) -> String? {
    if hasNotch { return settings.notchTrackTitle && !title.isEmpty ? title : nil }
    return visibleText(title: title, artist: artist, keepSong: settings.keepSongNameVisible,
                       keepArtist: settings.keepArtistVisible)
  }
}
