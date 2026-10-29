import Foundation

/// Step math for volume, brightness and keyboard backlight, matching macOS: 16 steps, quarter
/// steps with Shift+Option, and results snapped to the step grid so repeated presses stay tidy.
enum HUDLevelMath {
  static let steps = 16
  static let fineDivisor = 4

  static func stepSize(fine: Bool) -> Double {
    1.0 / Double(steps * (fine ? fineDivisor : 1))
  }

  static func clamp(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(1, max(0, value))
  }

  /// The level after one press. `direction` is +1 or -1. Off-grid levels (such as a slider
  /// dragged to 0.43) first snap to the next grid line in the pressed direction, like macOS.
  static func next(from level: Double, direction: Int, fine: Bool) -> Double {
    let size = stepSize(fine: fine)
    let start = clamp(level) / size
    let rounded = start.rounded()
    let onGrid = abs(start - rounded) < 1e-6
    let target: Double
    if direction > 0 {
      target = onGrid ? rounded + 1 : start.rounded(.up)
    } else {
      target = onGrid ? rounded - 1 : start.rounded(.down)
    }
    return clamp(target * size)
  }

  static func percent(_ level: Double) -> Int { Int((clamp(level) * 100).rounded()) }
}

/// SF Symbol choice per level, so the glyph itself tells the level at a glance.
enum HUDSymbol {
  static func volume(level: Double, muted: Bool) -> String {
    let level = HUDLevelMath.clamp(level)
    if muted || level <= 0 { return "speaker.slash.fill" }
    if level < 1.0 / 3 { return "speaker.wave.1.fill" }
    if level < 2.0 / 3 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
  }

  static func brightness(level: Double) -> String {
    HUDLevelMath.clamp(level) < 0.5 ? "sun.min.fill" : "sun.max.fill"
  }

  static func keyboard(level: Double) -> String {
    HUDLevelMath.clamp(level) < 0.5 ? "light.min" : "light.max"
  }
}
