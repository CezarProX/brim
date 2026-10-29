import Foundation

/// macOS moves volume in 16 steps; the room picker's -/+ buttons do the same.
enum SystemVolumeStepper {
  static let step: Float = 1.0 / 16

  static func next(level: Float, up: Bool) -> Float {
    let base = (level / step).rounded() * step
    return min(1, max(0, base + (up ? step : -step)))
  }
}
