import Foundation

extension JiggleDetector {
  /// Sensitivity 1 (hard to trigger) ... 5 (easy); 3 is "Balanced".
  init(sensitivity level: Int) {
    self.init()
    let s = min(5, max(1, level))
    minimumSwing = Self.minimumMovement(forSensitivity: s)
    requiredReversals = Self.reversals(forSensitivity: s)
  }
}

/// One shake per drag: the drag pasteboard's change count tells drags apart, so a long shake
/// can't open a panel for every reversal (and it needs no mouse-down from our own windows).
struct DragShakeGate {
  private var shakenDrag: Int?

  mutating func admit(drag: Int) -> Bool {
    guard shakenDrag != drag else { return false }
    shakenDrag = drag
    return true
  }
}

/// Decides what a shake does when floating trays may already be open.
enum FloatingTrayPolicy {
  enum Action: Equatable { case createNew, reuseLatest }

  static func onShake(openTrays: Int, multiple: Bool, limit: Int = AppSettings.maximumFloatingTrays) -> Action {
    if openTrays == 0 { return .createNew }
    return multiple && openTrays < limit ? .createNew : .reuseLatest
  }

  /// Where a new tray goes: beside the pointer for the first, cascading down-right after that.
  static func origin(near pointer: CGPoint, size: CGSize, index: Int, bounds: CGRect) -> CGPoint {
    var origin = CGPoint(x: pointer.x + 40 + CGFloat(index) * 26, y: pointer.y - size.height / 2 - CGFloat(index) * 26)
    origin.x = min(max(bounds.minX + 8, origin.x), bounds.maxX - size.width - 8)
    origin.y = min(max(bounds.minY + 8, origin.y), bounds.maxY - size.height - 8)
    return origin
  }
}
