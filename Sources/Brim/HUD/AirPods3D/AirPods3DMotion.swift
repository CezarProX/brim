import Foundation

/// Where the model is at a moment of its animation: it arrives small and turned away, springs
/// into its resting three-quarter pose, then eases into a slow continuous turn. Pure functions, so tests and snapshots are repeatable.
enum AirPods3DMotion {
  struct Pose: Equatable {
    var scale: CGFloat
    /// Turn around the vertical axis, radians.
    var yaw: CGFloat
    /// Lean towards the camera, radians.
    var pitch: CGFloat
  }

  static let introDuration: TimeInterval = 1.1
  /// Seconds for one full turn once settled.
  static let turnPeriod: TimeInterval = 8
  static let introScale: CGFloat = 0.62
  static let introYaw: CGFloat = -1.1
  /// After settling, the turn eases up to full speed over this long.
  static let turnRamp: TimeInterval = 1.2
  static let introPitch: CGFloat = 0.4
  /// Reduce Motion pose: a slight three-quarter view, never moving.
  static let restPose = Pose(scale: 1, yaw: -0.2, pitch: 0)

  /// Under-damped spring from 0 to 1 over `progress` 0...1, overshooting about 12% once.
  static func spring(_ progress: Double) -> Double {
    guard progress > 0 else { return 0 }
    guard progress < 1 else { return 1 }
    return 1 - exp(-6 * progress) * cos(9 * progress)
  }

  /// Seconds' worth of full-speed turning done `elapsed` seconds after settling, easing in from
  /// rest so there is no jolt when the spring ends.
  static func turnDistance(after elapsed: TimeInterval) -> TimeInterval {
    guard elapsed > 0 else { return 0 }
    if elapsed < turnRamp { return elapsed * elapsed / (2 * turnRamp) }
    return elapsed - turnRamp / 2
  }

  static func pose(at time: TimeInterval, reduceMotion: Bool = false) -> Pose {
    if reduceMotion { return restPose }
    let time = max(0, time)
    let settle = CGFloat(spring(time / introDuration))
    let turn = CGFloat(turnDistance(after: time - introDuration) / turnPeriod) * 2 * .pi
    return Pose(scale: introScale + (1 - introScale) * settle,
                yaw: restPose.yaw + introYaw * (1 - settle) + turn,
                pitch: introPitch * (1 - settle))
  }
}
