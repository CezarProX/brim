import CoreGraphics
import Foundation

/// Angle math for the ring, kept pure so it can be tested.
enum RingGeometry {
  /// Pointer closer to the center than this selects nothing.
  static let deadZone: CGFloat = 38

  /// Position of item `index` of `count` on a circle, starting at 12 o'clock, clockwise.
  static func offset(index: Int, count: Int, radius: CGFloat) -> CGSize {
    let angle = Double(index) / Double(max(1, count)) * 2 * .pi - .pi / 2
    return CGSize(width: radius * CGFloat(cos(angle)), height: radius * CGFloat(sin(angle)))
  }

  /// Clockwise angle in degrees from 12 o'clock, 0..<360, for a pointer offset from the ring's
  /// center in view coordinates (y grows downward).
  static func angle(dx: CGFloat, dy: CGFloat) -> Double {
    let degrees = atan2(Double(dx), Double(-dy)) * 180 / .pi
    return degrees < 0 ? degrees + 360 : degrees
  }

  /// The slot a pointer offset points at, or nil inside the dead zone.
  static func slot(dx: CGFloat, dy: CGFloat, count: Int, deadZone: CGFloat = RingGeometry.deadZone) -> Int? {
    guard count > 0, hypot(dx, dy) >= deadZone else { return nil }
    let wedge = 360.0 / Double(count)
    let shifted = (angle(dx: dx, dy: dy) + wedge / 2).truncatingRemainder(dividingBy: 360)
    return min(count - 1, Int(shifted / wedge))
  }

  /// The slot nearest to `index` in the given direction that is not empty, or nil when all are.
  static func nextFilled(_ filled: [Bool], from index: Int, step: Int) -> Int? {
    guard !filled.isEmpty, step != 0 else { return nil }
    var cursor = index
    for _ in filled.indices {
      cursor = ((cursor + step) % filled.count + filled.count) % filled.count
      if filled[cursor] { return cursor }
    }
    return nil
  }

  /// Which ring a scroll or number key moves to; wraps around.
  static func ring(after current: Int, step: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return ((current + step) % count + count) % count
  }

  /// The angle equivalent to `target` (mod 360) that is closest to `previous`, so an animated
  /// highlight turns the short way round instead of spinning back across 0/360.
  static func unwrapped(previous: Double, target: Double) -> Double {
    var value = target
    while value - previous > 180 { value -= 360 }
    while previous - value > 180 { value += 360 }
    return value
  }

  /// Center angle, clockwise from 12 o'clock, of slot `index`.
  static func centerAngle(index: Int, count: Int) -> Double {
    Double(index) / Double(max(1, count)) * 360
  }
}
