import Foundation

/// "Press ⌘Q twice to quit": the first press is swallowed and announced, a second press
/// within the window (or a long hold) goes through.
struct QuitGuardPolicy {
  enum Decision: Equatable {
    case announce  // swallow, show "Press ⌘Q again to quit"
    case swallow  // swallow quietly (auto-repeat during the first hold)
    case allow  // let the app receive it
  }

  static let confirmWindow: TimeInterval = 1.5
  static let holdThreshold: TimeInterval = 0.8
  private(set) var firstPress: Date?
  private(set) var armedBundle: String?

  /// `isRepeat` is the key's auto-repeat flag. Different apps never share a confirmation.
  mutating func decide(now: Date, bundleID: String?, isRepeat: Bool) -> Decision {
    if let firstPress, armedBundle == bundleID {
      let elapsed = now.timeIntervalSince(firstPress)
      if isRepeat {
        if elapsed >= Self.holdThreshold {
          reset()
          return .allow
        }
        return .swallow
      }
      if elapsed <= Self.confirmWindow {
        reset()
        return .allow
      }
    }
    if isRepeat { return .swallow }
    firstPress = now
    armedBundle = bundleID
    return .announce
  }

  mutating func reset() {
    firstPress = nil
    armedBundle = nil
  }
}
