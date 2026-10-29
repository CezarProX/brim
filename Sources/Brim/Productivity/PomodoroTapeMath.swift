import Foundation

/// Geometry and detent rules for the horizontal duration "tape" scrubber (1 min - 8 h).
enum PomodoroTapeMath {
  static let range = 1...480
  static let pointsPerMinute: CGFloat = 6
  /// How close (in points) the tape must be to a detent before it snaps to it.
  static let snapDistance: CGFloat = 4
  static let focusDetents = [5, 10, 15, 25, 50]
  static let breakDetents = [5, 10, 15]

  enum Tick: Equatable { case minor, major, detent }

  /// Minutes for a drag: the tape follows the pointer, so dragging left moves to a later time.
  static func rawMinutes(start: Int, translation: CGFloat, ppm: CGFloat = pointsPerMinute) -> Double {
    let value = Double(start) - Double(translation / ppm)
    return min(Double(range.upperBound), max(Double(range.lowerBound), value))
  }

  /// Rounds to a whole minute, but sticks to a detent when the tape is within `snapDistance` of it.
  static func snapped(
    _ raw: Double, detents: [Int], ppm: CGFloat = pointsPerMinute, snap: CGFloat = snapDistance
  ) -> Int {
    let nearest = detents.min { abs(Double($0) - raw) < abs(Double($1) - raw) }
    if let nearest, CGFloat(abs(Double(nearest) - raw)) * ppm <= snap { return nearest }
    return min(range.upperBound, max(range.lowerBound, Int(raw.rounded())))
  }

  /// Horizontal tape offset of a minute mark relative to the centered value.
  static func offset(of minute: Int, centeredOn value: Int, ppm: CGFloat = pointsPerMinute) -> CGFloat {
    CGFloat(minute - value) * ppm
  }

  /// The minute marks that fit in a window of `width` points around `value`.
  static func visibleMinutes(centeredOn value: Int, width: CGFloat, ppm: CGFloat = pointsPerMinute) -> ClosedRange<Int> {
    let half = Int((width / ppm / 2).rounded(.up)) + 1
    return max(range.lowerBound, value - half)...min(range.upperBound, value + half)
  }

  static func tick(for minute: Int, detents: [Int]) -> Tick {
    if detents.contains(minute) { return .detent }
    return minute % 5 == 0 ? .major : .minor
  }

  /// Haptics fire whenever the whole-minute value changes; detents are the firmer tick.
  static func hapticTick(from old: Int, to new: Int, detents: [Int]) -> Tick? {
    guard old != new else { return nil }
    return tick(for: new, detents: detents)
  }

  /// "25 min", "1 h 30 min", "8 h".
  static func label(minutes: Int) -> String {
    let hours = minutes / 60, rest = minutes % 60
    if hours == 0 { return "\(rest) min" }
    return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
  }
}
