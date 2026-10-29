import AppKit
import Darwin
import IOKit

/// Built-in display brightness through the private DisplayServices framework, loaded at runtime.
/// If the framework or a symbol is missing, or the display is an external monitor (which
/// DisplayServices refuses), every call fails and the caller lets macOS handle the key.
final class DisplayBrightnessControl: @unchecked Sendable {
  static let shared = DisplayBrightnessControl()
  private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
  private typealias SetFn = @convention(c) (UInt32, Float) -> Int32
  private let getBrightness: GetFn?
  private let setBrightness: SetFn?

  private init() {
    let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    guard let handle = dlopen(path, RTLD_LAZY) else {
      getBrightness = nil
      setBrightness = nil
      return
    }
    getBrightness = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
    setBrightness = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }
  }

  var isAvailable: Bool { getBrightness != nil && setBrightness != nil }

  /// The display under the pointer, falling back to the main display.
  static func targetDisplay(pointer: CGPoint = NSEvent.mouseLocation) -> CGDirectDisplayID {
    let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    return number.map { CGDirectDisplayID($0.uint32Value) } ?? CGMainDisplayID()
  }

  func level(display: CGDirectDisplayID) -> Double? {
    guard let getBrightness else { return nil }
    var value: Float = 0
    guard getBrightness(display, &value) == 0, value.isFinite else { return nil }
    return HUDLevelMath.clamp(Double(value))
  }

  @discardableResult
  func setLevel(_ level: Double, display: CGDirectDisplayID) -> Bool {
    guard let setBrightness else { return false }
    return setBrightness(display, Float(HUDLevelMath.clamp(level))) == 0
  }

  /// Steps the display and returns the new level, or nil when it can't be controlled.
  /// On the built-in panel the API's reading is checked against IOKit first: some macOS builds
  /// answer success but never move the backlight, and swallowing the key there breaks brightness.
  func step(direction: Int, fine: Bool, display: CGDirectDisplayID = targetDisplay()) -> Double? {
    guard let current = level(display: display) else { return nil }
    let panel = CGDisplayIsBuiltin(display) != 0 ? Self.builtInPanelLevel() : nil
    guard Self.isTrustworthy(api: current, panel: panel) else { return nil }
    let next = HUDLevelMath.next(from: current, direction: direction, fine: fine)
    return setLevel(next, display: display) ? next : nil
  }

  /// The broken builds read exactly full while the backlight is visibly lower. IOKit's backlight value
  /// is on another (linear) scale than DisplayServices' (perceptual) one, so a plain gap between the two
  /// is normal on a working Mac; only "stuck at full" while the panel is clearly dimmer is a lie.
  static func isTrustworthy(api: Double, panel: Double?) -> Bool {
    guard let panel else { return true }
    return !(api >= 0.999 && panel < 0.9)
  }

  static func panelFraction(value: Double, min: Double, max: Double) -> Double? {
    guard max > min else { return nil }
    return HUDLevelMath.clamp((value - min) / (max - min))
  }

  /// The built-in backlight's level as the hardware reports it (Apple silicon), or nil if unreadable.
  static func builtInPanelLevel() -> Double? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleARMBacklight"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    let property = IORegistryEntryCreateCFProperty(service, "IODisplayParameters" as CFString, kCFAllocatorDefault, 0)
    guard let parameters = property?.takeRetainedValue() as? [String: Any],
      let brightness = parameters["brightness"] as? [String: Any],
      let value = (brightness["value"] as? NSNumber)?.doubleValue,
      let max = (brightness["max"] as? NSNumber)?.doubleValue
    else { return nil }
    let min = (brightness["min"] as? NSNumber)?.doubleValue ?? 0
    return panelFraction(value: value, min: min, max: max)
  }
}
