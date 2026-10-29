import Foundation
import ObjectiveC

/// Keyboard backlight through CoreBrightness' `KeyboardBrightnessClient`, loaded at runtime.
/// Absent class, missing selector, or a Mac without a backlight all yield nil, so the key
/// event passes through untouched.
final class KeyboardBacklightControl: @unchecked Sendable {
  static let shared = KeyboardBacklightControl()
  private var client: NSObject?
  private var keyboardID: UInt64?

  private typealias GetFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
  private typealias SetFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

  private init() {
    guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
      let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
    else { return }
    let instance = cls.init()
    let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
    guard instance.responds(to: idsSelector),
      let ids = instance.perform(idsSelector)?.takeRetainedValue() as? [NSNumber], let first = ids.first
    else { return }
    client = instance
    keyboardID = first.uint64Value
  }

  var isAvailable: Bool { client != nil }

  func level() -> Double? {
    guard let client, let keyboardID else { return nil }
    let selector = NSSelectorFromString("brightnessForKeyboard:")
    guard client.responds(to: selector), let imp = client.method(for: selector) else { return nil }
    let value = unsafeBitCast(imp, to: GetFn.self)(client, selector, keyboardID)
    return value.isFinite ? HUDLevelMath.clamp(Double(value)) : nil
  }

  func setLevel(_ level: Double) -> Bool {
    guard let client, let keyboardID else { return false }
    let selector = NSSelectorFromString("setBrightness:forKeyboard:")
    guard client.responds(to: selector), let imp = client.method(for: selector) else { return false }
    return unsafeBitCast(imp, to: SetFn.self)(client, selector, Float(HUDLevelMath.clamp(level)), keyboardID)
  }

  func step(direction: Int, fine: Bool) -> Double? {
    guard let current = level() else { return nil }
    let next = HUDLevelMath.next(from: current, direction: direction, fine: fine)
    return setLevel(next) ? next : nil
  }
}
