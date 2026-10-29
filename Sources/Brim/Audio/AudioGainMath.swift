import Foundation

/// How a slider position maps to a gain. "Natural" follows loudness perception (a square law, so the
/// lower half of the slider is gentle); "Linear" is the raw multiplier.
enum VolumeCurve: String, CaseIterable, Identifiable, Sendable {
  case natural, linear
  var id: String { rawValue }
  var title: String { self == .natural ? "Natural" : "Linear" }
}

enum AudioGainMath {
  /// Slider range: 0...1 is attenuation, 1...maxBoost is boost (200% at most).
  static let maxSlider = 2.0
  /// Gain at the top of the slider (+6 dB). Boost is always linear in gain so it stays predictable.
  static let maxGain = 2.0

  static func clampSlider(_ value: Double) -> Double {
    value.isFinite ? min(max(value, 0), maxSlider) : 1
  }

  /// Linear multiplier for a slider position. 1.0 is untouched audio.
  static func gain(slider: Double, curve: VolumeCurve, muted: Bool = false) -> Float {
    guard !muted else { return 0 }
    let s = clampSlider(slider)
    if s <= 1 {
      switch curve {
      case .linear: return Float(s)
      case .natural: return Float(s * s)
      }
    }
    return Float(1 + (s - 1) * (maxGain - 1))
  }

  /// Inverse of `gain` below 100%, used to show a stored gain back on the slider.
  static func slider(forGain gain: Double, curve: VolumeCurve) -> Double {
    guard gain.isFinite, gain >= 0 else { return 1 }
    if gain <= 1 { return curve == .linear ? gain : gain.squareRoot() }
    return min(maxSlider, 1 + (gain - 1) / (maxGain - 1))
  }

  /// True when the audio would pass through unchanged, so no tap is needed.
  static func isNeutral(slider: Double, muted: Bool) -> Bool {
    !muted && abs(clampSlider(slider) - 1) < 0.0005
  }

  /// Soft limiter for boosted audio: transparent below the knee, tanh-shaped above, never past ±1.
  static func softClip(_ x: Float) -> Float {
    let knee: Float = 0.85
    let a = abs(x)
    guard a > knee else { return x }
    let over = (a - knee) / (1 - knee)
    let shaped = knee + (1 - knee) * tanhf(over)
    return x < 0 ? -shaped : shaped
  }

  static func percentLabel(_ slider: Double) -> String { "\(Int((clampSlider(slider) * 100).rounded()))%" }
}

/// Moves the applied gain toward the target a little each sample, so slider drags and mute never click.
struct GainSmoother: Sendable {
  private(set) var current: Float
  /// Largest change per sample. 1/2400 reaches any target in about 50 ms at 48 kHz.
  var step: Float

  init(initial: Float, step: Float = 1.0 / 2400) {
    current = initial
    self.step = step
  }

  mutating func next(toward target: Float) -> Float {
    if current < target { current = min(target, current + step) }
    else if current > target { current = max(target, current - step) }
    return current
  }
}
