import Foundation

extension AppSettings {
  var teleprompterEnabled: Bool {
    get { defaults.bool(forKey: "teleprompterEnabled") }
    set { defaults.set(newValue, forKey: "teleprompterEnabled") }
  }
  /// Default: ⌃⌥P.
  var teleprompterShortcut: DropletShortcut {
    get { .load("teleprompter", fallback: DropletShortcut(keyCode: 35, modifiers: 6144), from: defaults) }
    set { newValue.save("teleprompter", to: defaults) }
  }
  /// 1...20; see `TeleprompterMath.pointsPerSecond`.
  var teleprompterSpeed: Int {
    get { TeleprompterMath.clampLevel(defaults.object(forKey: "teleprompterSpeed") as? Int ?? 4) }
    set { defaults.set(TeleprompterMath.clampLevel(newValue), forKey: "teleprompterSpeed") }
  }
  /// 16...48 pt.
  var teleprompterFontSize: Int {
    get { min(48, max(16, defaults.object(forKey: "teleprompterFontSize") as? Int ?? 24)) }
    set { defaults.set(min(48, max(16, newValue)), forKey: "teleprompterFontSize") }
  }
  var teleprompterMirrored: Bool {
    get { defaults.bool(forKey: "teleprompterMirrored") }
    set { defaults.set(newValue, forKey: "teleprompterMirrored") }
  }
  var teleprompterHoverPause: Bool {
    get { defaults.object(forKey: "teleprompterHoverPause") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "teleprompterHoverPause") }
  }
  /// Keep the prompter out of screen recordings and screen sharing.
  var teleprompterHiddenFromCapture: Bool {
    get { defaults.object(forKey: "teleprompterHiddenFromCapture") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "teleprompterHiddenFromCapture") }
  }
  var teleprompterScript: String {
    get { defaults.string(forKey: "teleprompterScript") ?? "" }
    set { defaults.set(String(newValue.prefix(TeleprompterMath.maxScriptLength)), forKey: "teleprompterScript") }
  }
}
