import Foundation

/// Recognizes a quick shake of the pointer during a drag, using these rules:
/// each drag event must move at least `minimumSwing` points, a reversal is a heading whose dot
/// product with the previous one is below -0.3, and `requiredReversals` of them within `window`
/// seconds make a shake.
struct JiggleDetector {
  var minimumSwing: CGFloat = JiggleDetector.minimumMovement(forSensitivity: 3)
  var window: TimeInterval = 0.5
  var requiredReversals = JiggleDetector.reversals(forSensitivity: 3)
  static let reversalDot: CGFloat = -0.3
  private var last: CGPoint?
  private var heading: CGPoint?
  private var reversals: [TimeInterval] = []

  /// clamp(9 - 1.25 s, 3, 8) points per event.
  static func minimumMovement(forSensitivity s: Int) -> CGFloat { min(8, max(3, 9 - 1.25 * CGFloat(s))) }
  /// About 6 - s reversals, never fewer than 2.
  static func reversals(forSensitivity s: Int) -> Int { max(2, 6 - s) }

  /// Feeds one pointer sample; returns true once when a shake completes.
  mutating func add(x: CGFloat, y: CGFloat = 0, time: TimeInterval) -> Bool {
    reversals.removeAll { time - $0 > window }
    let point = CGPoint(x: x, y: y)
    defer { last = point }
    guard let previous = last else { return false }
    let dx = point.x - previous.x, dy = point.y - previous.y
    let length = (dx * dx + dy * dy).squareRoot()
    guard length > minimumSwing else { return false }
    let unit = CGPoint(x: dx / length, y: dy / length)
    if let heading, heading.x * unit.x + heading.y * unit.y < Self.reversalDot { reversals.append(time) }
    heading = unit
    guard reversals.count >= requiredReversals else { return false }
    reset()
    return true
  }

  mutating func reset() {
    last = nil
    heading = nil
    reversals.removeAll()
  }
}
